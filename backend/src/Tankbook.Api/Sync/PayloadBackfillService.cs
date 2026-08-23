using System.Data;
using Dapper;

namespace Tankbook.Api.Sync;

/// <summary>Summary of one backfill run.</summary>
public sealed record BackfillResult(long RecordsProcessed, long BatchesRun);

/// <summary>
/// Batched, idempotent, resumable server-side payload backfill (docs/SYNC.md
/// "Migrating payloads - server-side backfill"). Applies the declarative
/// transforms registered in <c>payload_migrations</c> to every record still at
/// the source version, rewriting <c>payload</c> and <c>schema_version</c> in
/// place. Backfill is NOT a user edit, so it NEVER allocates new SCNs - that
/// would fake a change on every device and stampede the pull stream. Progress
/// is durable per row: an interrupted run simply resumes on the next invocation
/// because only rows still at <c>from_version</c> are candidates.
/// </summary>
public sealed class PayloadBackfillService
{
    private const long SafetyCap = 1_000_000;

    private readonly IDbConnection _db;
    private readonly PayloadTransformEngine _engine;
    private readonly int _batchSize;

    public PayloadBackfillService(IDbConnection db, PayloadTransformEngine engine, int batchSize = 500)
    {
        _db = db;
        _engine = engine;
        _batchSize = batchSize;
    }

    /// <summary>
    /// Runs every registered migration until a full pass processes no rows.
    /// Chains (v1 -&gt; v2 -&gt; v3) are drained in one call because migrations are
    /// processed in from_version order and re-queried each pass.
    /// </summary>
    public async Task<BackfillResult> RunAsync(CancellationToken cancellationToken = default)
    {
        var migrations = (await _db.QueryAsync<MigrationSpec>(
            new CommandDefinition(
                "SELECT entity_type, from_version, to_version, transform FROM payload_migrations",
                cancellationToken: cancellationToken))).ToList();

        long total = 0;
        long batches = 0;

        while (true)
        {
            long processedThisPass = 0;
            foreach (var migration in migrations.OrderBy(m => m.from_version).ThenBy(m => m.entity_type, StringComparer.Ordinal))
            {
                var (processed, batchesRun) = await ProcessMigrationAsync(migration, cancellationToken);
                processedThisPass += processed;
                batches += batchesRun;
            }

            total += processedThisPass;
            if (processedThisPass == 0)
            {
                break;
            }

            if (total > SafetyCap)
            {
                throw new InvalidOperationException($"Payload backfill exceeded the {SafetyCap}-row safety cap; aborting.");
            }
        }

        return new BackfillResult(total, batches);
    }

    private async Task<(long Processed, long Batches)> ProcessMigrationAsync(MigrationSpec migration, CancellationToken cancellationToken)
    {
        long processed = 0;
        long batches = 0;

        while (true)
        {
            var rows = (await _db.QueryAsync<RecordRow>(
                new CommandDefinition(
                    """
                    SELECT account_id, id, payload::text AS payload
                    FROM records
                    WHERE entity_type = @entity_type AND schema_version = @from_version
                    ORDER BY account_id, id
                    LIMIT @batch_size
                    """,
                    new { migration.entity_type, migration.from_version, batch_size = _batchSize },
                    cancellationToken: cancellationToken))).ToList();

            if (rows.Count == 0)
            {
                break;
            }

            using var transaction = _db.BeginTransaction();
            foreach (var row in rows)
            {
                var transformed = _engine.Apply(row.payload, migration.transform);
                // The schema_version guard makes the UPDATE idempotent under
                // concurrent or repeated runs (a row already migrated is not a
                // candidate any more). scn is never touched.
                await _db.ExecuteAsync(
                    new CommandDefinition(
                        """
                        UPDATE records
                        SET payload = @payload::jsonb, schema_version = @to_version
                        WHERE account_id = @account_id AND id = @id AND schema_version = @from_version
                        """,
                        new
                        {
                            payload = transformed,
                            migration.to_version,
                            row.account_id,
                            row.id,
                            migration.from_version,
                        },
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                processed++;
            }

            transaction.Commit();
            batches++;
        }

        return (processed, batches);
    }

    private sealed record MigrationSpec(string entity_type, int from_version, int to_version, string transform);

    private sealed record RecordRow(Guid account_id, Guid id, string payload);
}
