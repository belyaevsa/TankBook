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
/// one place a race can corrupt a user's history silently, so a whole push batch
/// runs in ONE transaction that commits once (RV.105). Per-record transactions
/// cost ~578 ms each on the production host (a fixed per-record cost,
/// independent of payload size - the commit's fsync), so a 200-record batch was
/// 92-115 s of pure commit time against the client's 120 s upload budget. One
/// commit per batch collapsed that.
///
/// Inside the single transaction the batch is applied in a constant number of
/// database round trips, independent of batch size (RV.154): one multi-row
/// FOR UPDATE read of every target row, one contiguous SCN range allocation for
/// the batch's writes, and one multi-row write each for brand-new and for
/// existing records. A per-record loop would serialize ~3 x record-count round
/// trips - the production logs show ~145 ms per round trip on the database
/// link, so 200 records was ~90 s of pure round-trip time on top of the commit.
///
/// Partial batch acceptance is mechanical: a conflict or an idempotent replay
/// is a no-op inside the transaction (the row is read but not written), never
/// a rollback, so one conflicting record cannot take the rest of the batch
/// down. The FOR UPDATE locks are taken by the single batched read - rows are
/// locked in index order in one statement, so no lock is lost and concurrent
/// batches serialize on the same rows in the same order. Committed SCNs stay
/// contiguous and commit in order, which is what lets a pull cursor page the
/// stream without ever skipping an in-flight commit.
/// </summary>
public sealed class SyncRepository
{
    private const string RecordColumns = """
        SELECT id, entity_type, schema_version, scn, payload::text AS payload, client_updated_at, deleted
        FROM records
        """;

    /// <summary>
    /// One multi-row insert of a whole batch's brand-new records (RV.154).
    /// The arrays are unrolled by unnest into one statement, so the whole
    /// insert set costs one round trip whatever its size. A multi-argument
    /// unnest may not carry a typed column definition list; the element types
    /// come from the Npgsql-typed array parameters, so the alias names columns
    /// only.
    /// </summary>
    private const string InsertManySql = """
        INSERT INTO records (account_id, id, entity_type, schema_version, scn, payload, client_updated_at, deleted, origin_device)
        SELECT @AccountId, u.id, u.entity_type, u.schema_version, u.scn, u.payload::jsonb, u.client_updated_at, u.deleted, @OriginDevice
        FROM unnest(@Ids, @EntityTypes, @SchemaVersions, @Scns, @Payloads, @ClientUpdatedAts, @Deleteds)
            AS u(id, entity_type, schema_version, scn, payload, client_updated_at, deleted)
        """;

    /// <summary>
    /// One multi-row update of a whole batch's existing records. Every row is
    /// already locked by the batch's single FOR UPDATE read, so no lock is
    /// lost by deferring the writes to one statement.
    /// </summary>
    private const string UpdateManySql = """
        UPDATE records AS r
        SET entity_type = u.entity_type,
            schema_version = u.schema_version,
            scn = u.scn,
            payload = u.payload::jsonb,
            client_updated_at = u.client_updated_at,
            deleted = u.deleted,
            origin_device = @OriginDevice
        FROM unnest(@Ids, @EntityTypes, @SchemaVersions, @Scns, @Payloads, @ClientUpdatedAts, @Deleteds)
            AS u(id, entity_type, schema_version, scn, payload, client_updated_at, deleted)
        WHERE r.account_id = @AccountId AND r.id = u.id
        """;

    private readonly IDbConnection _db;

    /// <summary>A write the batch will perform once its SCN block is allocated.</summary>
    private sealed record PendingWrite(BatchChange Change, int ResultIndex, bool Insert)
    {
        public long Scn { get; set; }
    }

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
    /// Applies a whole validated push batch in one transaction with a constant
    /// number of database round trips. Every change is first resolved against
    /// the batch's single multi-row FOR UPDATE read: idempotent (a replayed
    /// new-record push, baseScn 0 against an existing id) and conflicting
    /// changes settle in memory and consume nothing; accepted changes are
    /// written in one multi-row statement each for inserts and updates, with
    /// their SCNs drawn from one contiguous range allocated in this same
    /// transaction. A conflict or an idempotent replay is a no-op, never a
    /// rollback, so partial batch acceptance survives (docs/SYNC.md). An id
    /// repeated inside one batch resolves against the batch's own first write
    /// for that id, mirroring the per-record path, which saw its own uncommitted
    /// writes on re-read.
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
            try
            {
                // One multi-row read that locks every target row: the FOR
                // UPDATE guarantee survives batching - the whole batch's rows
                // are locked by this one statement instead of one round trip
                // and one lock acquisition per record.
                var rows = await _db.QueryAsync<RecordRow>(new CommandDefinition(
                    RecordColumns + " WHERE account_id = @AccountId AND id = ANY(@Ids) FOR UPDATE",
                    new { AccountId = accountId, Ids = changes.Select(c => c.Id).ToArray() },
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                var currentById = new Dictionary<Guid, RecordRow>();
                foreach (var row in rows)
                {
                    currentById[row.id] = row;
                }

                // Resolve every change against its current row in batch order.
                // A change that must write joins the writes list (allocation
                // slot order); replays and conflicts settle here unless they
                // reference a write made earlier in this same batch, whose SCN
                // is only known once the range is allocated below.
                var writes = new List<PendingWrite>(changes.Count);
                var lastWriteSlot = new Dictionary<Guid, int>();
                var replayAtWrite = new Dictionary<int, int>();
                var conflictAtWrite = new Dictionary<int, int>();
                for (var i = 0; i < changes.Count; i++)
                {
                    var change = changes[i];
                    if (lastWriteSlot.TryGetValue(change.Id, out var slot))
                    {
                        // The batch already wrote this id this pass. Only a
                        // baseScn of 0 can be a legitimate replay (the client
                        // cannot know an SCN allocated inside this batch);
                        // anything else is a conflict against that write.
                        if (change.BaseScn == 0)
                        {
                            replayAtWrite[i] = slot;
                        }
                        else
                        {
                            conflictAtWrite[i] = slot;
                        }

                        continue;
                    }

                    if (currentById.TryGetValue(change.Id, out var current))
                    {
                        if (change.BaseScn == 0)
                        {
                            // Idempotent replay of a new-record push: same outcome, no write.
                            results[i] = new ApplyResult(ApplyStatus.Accepted, current.scn, null);
                        }
                        else if (change.BaseScn == current.scn)
                        {
                            slot = writes.Count;
                            writes.Add(new PendingWrite(change, i, Insert: false));
                            lastWriteSlot[change.Id] = slot;
                        }
                        else
                        {
                            // A stale base: no-op inside the batch, reported as a conflict.
                            results[i] = new ApplyResult(ApplyStatus.Conflict, 0, ToSyncRecord(current));
                        }
                    }
                    else
                    {
                        slot = writes.Count;
                        writes.Add(new PendingWrite(change, i, Insert: true));
                        lastWriteSlot[change.Id] = slot;
                    }
                }

                if (writes.Count == 0)
                {
                    // Nothing but replays and conflicts: no SCN consumed, no write.
                    await transaction.RollbackAsync(cancellationToken);
                    return new BatchApplyResult(results, Commits: 0);
                }

                // One contiguous SCN block for the whole batch, allocated in one
                // round trip; slot s gets first + s, in batch order.
                var blockLast = await ScnAllocator.AllocateRangeAsync(_db, transaction, accountId, writes.Count);
                var blockFirst = blockLast - writes.Count + 1;
                for (var s = 0; s < writes.Count; s++)
                {
                    writes[s].Scn = blockFirst + s;
                    results[writes[s].ResultIndex] = new ApplyResult(ApplyStatus.Accepted, writes[s].Scn, null);
                }

                foreach (var (index, slot) in replayAtWrite)
                {
                    results[index] = new ApplyResult(ApplyStatus.Accepted, writes[slot].Scn, null);
                }

                foreach (var (index, slot) in conflictAtWrite)
                {
                    results[index] = new ApplyResult(ApplyStatus.Conflict, 0, ToSyncRecord(writes[slot].Change, writes[slot].Scn));
                }

                // One multi-row statement for the inserts and one for the
                // updates: the whole write set, whatever its size.
                var inserts = writes.Where(w => w.Insert).ToArray();
                if (inserts.Length > 0)
                {
                    await _db.ExecuteAsync(new CommandDefinition(
                        InsertManySql,
                        WriteParams(accountId, deviceId, inserts),
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                }

                var updates = writes.Where(w => !w.Insert).ToArray();
                if (updates.Length > 0)
                {
                    await _db.ExecuteAsync(new CommandDefinition(
                        UpdateManySql,
                        WriteParams(accountId, deviceId, updates),
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                }

                await transaction.CommitAsync(cancellationToken);
                return new BatchApplyResult(results, Commits: 1);
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

    /// <summary>
    /// Renders the record a batch write produced, for a conflict reported
    /// against a row the batch itself wrote earlier in the same pass.
    /// </summary>
    private static SyncRecord ToSyncRecord(BatchChange change, long scn)
    {
        using var document = JsonDocument.Parse(change.PayloadJson);
        return new SyncRecord(
            change.Id,
            change.EntityType,
            change.SchemaVersion,
            scn,
            document.RootElement.Clone(),
            change.ClientUpdatedAt,
            change.Deleted);
    }

    /// <summary>Column arrays for one multi-row insert/update statement, aligned by position.</summary>
    private static object WriteParams(Guid accountId, Guid deviceId, IReadOnlyList<PendingWrite> writes)
        => new
        {
            AccountId = accountId,
            OriginDevice = deviceId,
            Ids = writes.Select(w => w.Change.Id).ToArray(),
            EntityTypes = writes.Select(w => w.Change.EntityType).ToArray(),
            SchemaVersions = writes.Select(w => w.Change.SchemaVersion).ToArray(),
            Scns = writes.Select(w => w.Scn).ToArray(),
            Payloads = writes.Select(w => w.Change.PayloadJson).ToArray(),
            ClientUpdatedAts = writes.Select(w => w.Change.ClientUpdatedAt).ToArray(),
            Deleteds = writes.Select(w => w.Change.Deleted).ToArray(),
        };

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
