using System.Data;
using System.Data.Common;
using System.Text.Json;
using Dapper;
using Tankbook.Api.Data;

namespace Tankbook.Api.Sync;

/// <summary>
/// One records row, read with the payload as text (jsonb::text). client_updated_at
/// is a DateTime (not DateTimeOffset) because Npgsql maps timestamptz to a
/// UTC DateTime on read; Dapper's positional-record materializer requires the
/// constructor parameter type to match the column type exactly.
/// </summary>
public sealed record RecordRow(
    Guid id,
    string entity_type,
    int schema_version,
    long scn,
    string payload,
    DateTime client_updated_at,
    bool deleted);

/// <summary>How a push change resolved against the server's current record.</summary>
public enum ApplyStatus
{
    Accepted,
    Conflict,
}

/// <summary>Result of applying one change: accepted with the new SCN, or a conflict with the current record.</summary>
public sealed record ApplyResult(ApplyStatus Status, long Scn, SyncRecord? Current);

/// <summary>
/// One prepared change in a push batch (docs/SYNC.md). The service has already
/// validated it; the repository never re-interprets the payload, it only writes
/// it (hard rule 9).
/// </summary>
public sealed record BatchChange(
    Guid Id,
    string EntityType,
    int SchemaVersion,
    long BaseScn,
    string PayloadJson,
    DateTimeOffset ClientUpdatedAt,
    bool Deleted);

/// <summary>
/// Outcome of applying a whole push batch. <see cref="Results"/> is aligned with
/// the input changes; <see cref="Commits"/> is how many transactions the batch
/// actually committed - the RV.105 regression signal, since the fix's whole
/// point is that a 200-record batch costs one commit, not 200.
/// </summary>
public sealed record BatchApplyResult(IReadOnlyList<ApplyResult> Results, int Commits);

/// <summary>
/// Database access for the sync endpoints (docs/SYNC.md). The apply path is the
/// one place a race can corrupt a user's history silently, so since RV.105
/// (2026-09-07) a whole push batch runs in ONE transaction: it locks each target
/// record row, allocates SCNs from <see cref="ScnAllocator"/> inside that same
/// transaction, and writes accepted rows before committing once. Per-record
/// transactions cost ~578 ms each on the production host (a fixed per-record
/// cost, independent of payload size - the commit's fsync), so a 200-record
/// batch was 92-115 s of pure commit time against the client's 120 s upload
/// budget. One commit per batch collapses that. Partial batch acceptance is
/// unchanged and mechanical: a conflict or an idempotent replay is a no-op
/// inside the transaction (the row is read but not written), never a rollback.
/// Committed SCNs stay contiguous and commit in order, which is what lets a pull
/// cursor page the stream without ever skipping an in-flight commit.
/// </summary>
public sealed class SyncRepository
{
    private const string RecordColumns = """
        SELECT id, entity_type, schema_version, scn, payload::text AS payload, client_updated_at, deleted
        FROM records
        """;

    private const string InsertSql = """
        INSERT INTO records (account_id, id, entity_type, schema_version, scn, payload, client_updated_at, deleted, origin_device)
        VALUES (@AccountId, @Id, @EntityType, @SchemaVersion, @Scn, @Payload::jsonb, @ClientUpdatedAt, @Deleted, @OriginDevice)
        """;

    private const string UpdateSql = """
        UPDATE records
        SET entity_type = @EntityType,
            schema_version = @SchemaVersion,
            scn = @Scn,
            payload = @Payload::jsonb,
            client_updated_at = @ClientUpdatedAt,
            deleted = @Deleted,
            origin_device = @OriginDevice
        WHERE account_id = @AccountId AND id = @Id
        """;

    private readonly IDbConnection _db;

    public SyncRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>
    /// True when the account still exists and is not deleted, and the device
    /// still exists, is not revoked, and belongs to that account. False means
    /// the caller answers 410 (docs/API.md: revoked device / deleted account).
    /// </summary>
    public async Task<bool> IsDeviceActiveAsync(Guid accountId, Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleAsync<bool>(new CommandDefinition(
                """
                SELECT EXISTS (
                    SELECT 1 FROM accounts a
                    JOIN devices d ON d.account_id = a.id AND d.id = @DeviceId
                    WHERE a.id = @AccountId AND a.deleted_at IS NULL AND d.revoked_at IS NULL
                )
                """,
                new { AccountId = accountId, DeviceId = deviceId },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// Applies a whole validated push batch in one transaction. Each change is
    /// resolved against its current row (idempotent: a replayed new-record push,
    /// baseScn 0 against an existing id, returns the existing SCN without a write
    /// or an allocation), accepted changes are written with an SCN allocated in
    /// this same transaction, and the transaction commits once at the end.
    /// Conflicts do not roll the batch back - a conflicting change is simply not
    /// written and is reported as a conflict (docs/SYNC.md partial acceptance).
    /// </summary>
    public async Task<BatchApplyResult> ApplyBatchAsync(
        Guid accountId,
        Guid deviceId,
        IReadOnlyList<BatchChange> changes,
        CancellationToken cancellationToken)
    {
        var results = new ApplyResult[changes.Count];
        if (changes.Count == 0)
        {
            return new BatchApplyResult(results, Commits: 0);
        }

        var opened = await OpenIfNeededAsync();
        try
        {
            var connection = (DbConnection)_db;
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            var wrote = false;
            try
            {
                for (var i = 0; i < changes.Count; i++)
                {
                    var change = changes[i];
                    var current = await _db.QuerySingleOrDefaultAsync<RecordRow>(new CommandDefinition(
                        RecordColumns + " WHERE account_id = @AccountId AND id = @Id FOR UPDATE",
                        new { AccountId = accountId, Id = change.Id },
                        transaction: transaction,
                        cancellationToken: cancellationToken));

                    if (current is null)
                    {
                        var scn = await ScnAllocator.AllocateAsync(transaction, accountId);
                        await _db.ExecuteAsync(new CommandDefinition(
                            InsertSql,
                            new
                            {
                                AccountId = accountId,
                                Id = change.Id,
                                EntityType = change.EntityType,
                                SchemaVersion = change.SchemaVersion,
                                Scn = scn,
                                Payload = change.PayloadJson,
                                ClientUpdatedAt = change.ClientUpdatedAt,
                                Deleted = change.Deleted,
                                OriginDevice = deviceId,
                            },
                            transaction: transaction,
                            cancellationToken: cancellationToken));
                        wrote = true;
                        results[i] = new ApplyResult(ApplyStatus.Accepted, scn, null);
                    }
                    else if (change.BaseScn == 0)
                    {
                        // Idempotent replay of a new-record push: same outcome, no write.
                        results[i] = new ApplyResult(ApplyStatus.Accepted, current.scn, null);
                    }
                    else if (change.BaseScn == current.scn)
                    {
                        var scn = await ScnAllocator.AllocateAsync(transaction, accountId);
                        await _db.ExecuteAsync(new CommandDefinition(
                            UpdateSql,
                            new
                            {
                                AccountId = accountId,
                                Id = change.Id,
                                EntityType = change.EntityType,
                                SchemaVersion = change.SchemaVersion,
                                Scn = scn,
                                Payload = change.PayloadJson,
                                ClientUpdatedAt = change.ClientUpdatedAt,
                                Deleted = change.Deleted,
                                OriginDevice = deviceId,
                            },
                            transaction: transaction,
                            cancellationToken: cancellationToken));
                        wrote = true;
                        results[i] = new ApplyResult(ApplyStatus.Accepted, scn, null);
                    }
                    else
                    {
                        // A stale base: no-op inside the batch, reported as a conflict.
                        results[i] = new ApplyResult(ApplyStatus.Conflict, 0, ToSyncRecord(current));
                    }
                }

                if (wrote)
                {
                    await transaction.CommitAsync(cancellationToken);
                }
                else
                {
                    await transaction.RollbackAsync(cancellationToken);
                }

                return new BatchApplyResult(results, wrote ? 1 : 0);
            }
            catch
            {
                await transaction.RollbackAsync(cancellationToken);
                throw;
            }
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Pulls records strictly ordered by SCN after <paramref name="since"/>, at most <paramref name="limit"/>.</summary>
    public async Task<IReadOnlyList<SyncRecord>> PullAsync(
        Guid accountId,
        long since,
        int limit,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<RecordRow>(new CommandDefinition(
                RecordColumns + " WHERE account_id = @AccountId AND scn > @Since ORDER BY scn LIMIT @Limit",
                new { AccountId = accountId, Since = since, Limit = limit },
                cancellationToken: cancellationToken));

            return rows.Select(ToSyncRecord).ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Advances the device's server-side pull cursor and last-seen stamp.</summary>
    public async Task UpdateDeviceCursorAsync(Guid deviceId, long nextSince, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE devices SET last_pull_scn = @NextSince, last_seen_at = now() WHERE id = @DeviceId",
                new { NextSince = nextSince, DeviceId = deviceId },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    private static SyncRecord ToSyncRecord(RecordRow row)
    {
        using var document = JsonDocument.Parse(row.payload);
        var updatedAt = new DateTimeOffset(DateTime.SpecifyKind(row.client_updated_at, DateTimeKind.Utc));
        return new SyncRecord(
            row.id,
            row.entity_type,
            row.schema_version,
            row.scn,
            document.RootElement.Clone(),
            updatedAt,
            row.deleted);
    }

    private async Task<bool> OpenIfNeededAsync()
    {
        if (_db.State == ConnectionState.Open)
        {
            return false;
        }

        await ((DbConnection)_db).OpenAsync();
        return true;
    }
}
