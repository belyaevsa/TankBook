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
/// Database access for the sync endpoints (docs/SYNC.md). The apply-change path
/// is the one place a race can corrupt a user's history silently, so it runs in
/// a single transaction that locks the target record row, allocates the SCN from
/// <see cref="ScnAllocator"/> inside that same transaction, and writes the row
/// before committing - committed SCNs are therefore contiguous and commit in
/// order, which is what lets a pull cursor page the stream without ever skipping
/// an in-flight commit.
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
    /// Applies one validated change in its own transaction. Idempotent: a replayed
    /// new-record push (baseScn 0 against an existing id) returns the same accepted
    /// outcome and existing SCN without a second row or a second allocation.
    /// </summary>
    public async Task<ApplyResult> ApplyChangeAsync(
        Guid accountId,
        Guid deviceId,
        string entityType,
        int schemaVersion,
        Guid id,
        long baseScn,
        string payloadJson,
        DateTimeOffset clientUpdatedAt,
        bool deleted,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var connection = (DbConnection)_db;
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                var current = await _db.QuerySingleOrDefaultAsync<RecordRow>(new CommandDefinition(
                    RecordColumns + " WHERE account_id = @AccountId AND id = @Id FOR UPDATE",
                    new { AccountId = accountId, Id = id },
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
                            Id = id,
                            EntityType = entityType,
                            SchemaVersion = schemaVersion,
                            Scn = scn,
                            Payload = payloadJson,
                            ClientUpdatedAt = clientUpdatedAt,
                            Deleted = deleted,
                            OriginDevice = deviceId,
                        },
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                    await transaction.CommitAsync(cancellationToken);
                    return new ApplyResult(ApplyStatus.Accepted, scn, null);
                }

                if (baseScn == 0)
                {
                    // Idempotent replay of a new-record push: same outcome, no write.
                    await transaction.RollbackAsync(cancellationToken);
                    return new ApplyResult(ApplyStatus.Accepted, current.scn, null);
                }

                if (baseScn == current.scn)
                {
                    var scn = await ScnAllocator.AllocateAsync(transaction, accountId);
                    await _db.ExecuteAsync(new CommandDefinition(
                        UpdateSql,
                        new
                        {
                            AccountId = accountId,
                            Id = id,
                            EntityType = entityType,
                            SchemaVersion = schemaVersion,
                            Scn = scn,
                            Payload = payloadJson,
                            ClientUpdatedAt = clientUpdatedAt,
                            Deleted = deleted,
                            OriginDevice = deviceId,
                        },
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                    await transaction.CommitAsync(cancellationToken);
                    return new ApplyResult(ApplyStatus.Accepted, scn, null);
                }

                await transaction.RollbackAsync(cancellationToken);
                return new ApplyResult(ApplyStatus.Conflict, 0, ToSyncRecord(current));
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
