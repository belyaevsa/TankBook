using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Sync;

namespace Tankbook.Api.Tests;

/// <summary>
/// Server-side payload backfill (docs/SYNC.md "Migrating payloads"). Batched,
/// idempotent, resumable; rewrites payload + schema_version in place and NEVER
/// allocates new SCNs - backfill is not a user edit and must not stampede the
/// pull stream. Real Postgres because SQL semantics are the subject.
/// </summary>
public class PayloadBackfillTests : IClassFixture<PostgresFixture>
{
    private const string TransformV1ToV2 =
        """
        [
          { "op": "rename", "from": "name", "to": "displayName" },
          { "op": "wrap", "name": "price", "into": "money", "as": "amount" }
        ]
        """;

    private static readonly string ExpectedV2Payload = """{"displayName":"Volvo","money":{"amount":5}}""";

    private readonly PostgresFixture _fixture;

    public PayloadBackfillTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task Backfill_RewritesRecords_KeepsScnUntouched_AndAllocatesNoScns()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = await SeedAccountAsync(db);
        var vehicleIds = await InsertRecordsAsync(db, accountId, entityType: "vehicle", count: 3);
        var stationId = (await InsertRecordsAsync(db, accountId, entityType: "station", count: 1, startScn: 10)).Single();
        await RegisterMigrationAsync(db, "vehicle", 1, 2, TransformV1ToV2);

        var result = await RunAsync(db);

        Assert.Equal(3, result.RecordsProcessed);
        foreach (var id in vehicleIds)
        {
            await AssertRecordAtVersionAsync(db, accountId, id, schemaVersion: 2, ExpectedV2Payload);
        }

        // Unrelated entity untouched, including its scn.
        var stationScn = await db.QuerySingleAsync<long>(
            "SELECT scn FROM records WHERE account_id = @accountId AND id = @id", new { accountId, id = stationId });
        Assert.Equal(10, stationScn);

        // Backfill never allocates SCNs: no account_seq rows were created.
        var seqCount = await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM account_seq WHERE account_id = @accountId", new { accountId });
        Assert.Equal(0, seqCount);
    }

    [SkippableFact]
    public async Task Backfill_ReRunning_IsANoOp()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = await SeedAccountAsync(db);
        var vehicleIds = await InsertRecordsAsync(db, accountId, entityType: "vehicle", count: 3);
        await RegisterMigrationAsync(db, "vehicle", 1, 2, TransformV1ToV2);

        var first = await RunAsync(db);
        var scnsAfterFirst = await db.QueryAsync<long>(
            "SELECT scn FROM records WHERE account_id = @accountId ORDER BY scn", new { accountId });

        var second = await RunAsync(db);

        Assert.Equal(0, second.RecordsProcessed);
        Assert.Equal(0, second.BatchesRun);
        var scnsAfterSecond = await db.QueryAsync<long>(
            "SELECT scn FROM records WHERE account_id = @accountId ORDER BY scn", new { accountId });
        Assert.Equal(scnsAfterFirst, scnsAfterSecond);

        foreach (var id in vehicleIds)
        {
            await AssertRecordAtVersionAsync(db, accountId, id, schemaVersion: 2, ExpectedV2Payload);
        }

        // The first run's own summary reflects the three rewritten records.
        Assert.Equal(3, first.RecordsProcessed);
    }

    [SkippableFact]
    public async Task Backfill_ResumesAfterInterruption()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = await SeedAccountAsync(db);
        var vehicleIds = await InsertRecordsAsync(db, accountId, entityType: "vehicle", count: 4);
        await RegisterMigrationAsync(db, "vehicle", 1, 2, TransformV1ToV2);

        // Simulate an interrupted earlier run: the first two rows were already
        // rewritten and committed before the job died.
        var alreadyDone = vehicleIds.Take(2).ToList();
        var remaining = vehicleIds.Skip(2).ToList();
        foreach (var id in alreadyDone)
        {
            await db.ExecuteAsync(
                "UPDATE records SET payload = @payload::jsonb, schema_version = 2 WHERE account_id = @accountId AND id = @id",
                new { payload = ExpectedV2Payload, accountId, id });
        }

        var result = await RunAsync(db, batchSize: 1);

        Assert.Equal(2, result.RecordsProcessed);
        foreach (var id in alreadyDone.Concat(remaining))
        {
            await AssertRecordAtVersionAsync(db, accountId, id, schemaVersion: 2, ExpectedV2Payload);
        }
    }

    [SkippableFact]
    public async Task Backfill_DrainsVersionChains_InOneRun()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = await SeedAccountAsync(db);
        var vehicleIds = await InsertRecordsAsync(db, accountId, entityType: "vehicle", count: 2);
        await RegisterMigrationAsync(db, "vehicle", 1, 2, TransformV1ToV2);
        await RegisterMigrationAsync(
            db, "vehicle", 2, 3, """[ { "op": "addDefault", "name": "country", "value": "DE" } ]""");

        var result = await RunAsync(db);

        // v1 -> v2 -> v3 drained in one call. RecordsProcessed counts rewrites,
        // so each of the two records is counted once per hop (2 records x 2 hops).
        Assert.Equal(4, result.RecordsProcessed);
        foreach (var id in vehicleIds)
        {
            await AssertRecordAtVersionAsync(
                db, accountId, id, schemaVersion: 3,
                """{"displayName":"Volvo","money":{"amount":5},"country":"DE"}""");
        }
    }

    private async Task<BackfillResult> RunAsync(NpgsqlConnection db, int batchSize = 2)
    {
        var service = new PayloadBackfillService(db, new PayloadTransformEngine(), batchSize);
        return await service.RunAsync();
    }

    private async Task<NpgsqlConnection> NewMigratedDbAsync()
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static async Task<Guid> SeedAccountAsync(NpgsqlConnection db)
    {
        var accountId = Guid.NewGuid();
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@id, @email)",
            new { id = accountId, email = $"backfill-{Guid.NewGuid():N}@example.com" });
        return accountId;
    }

    private static async Task<List<Guid>> InsertRecordsAsync(
        NpgsqlConnection db, Guid accountId, string entityType, int count, int startScn = 1)
    {
        var ids = new List<Guid>();
        for (var i = 0; i < count; i++)
        {
            var id = Guid.NewGuid();
            await db.ExecuteAsync(
                """
                INSERT INTO records (account_id, id, entity_type, scn, payload, client_updated_at, schema_version)
                VALUES (@accountId, @id, @entityType, @scn, '{"name":"Volvo","price":5}'::jsonb, now(), 1)
                """,
                new { accountId, id, entityType, scn = startScn + i });
            ids.Add(id);
        }

        return ids;
    }

    private static async Task RegisterMigrationAsync(
        NpgsqlConnection db, string entityType, int fromVersion, int toVersion, string transform)
    {
        await db.ExecuteAsync(
            """
            INSERT INTO payload_migrations (entity_type, from_version, to_version, transform)
            VALUES (@entityType, @fromVersion, @toVersion, @transform::jsonb)
            """,
            new { entityType, fromVersion, toVersion, transform });
    }

    private static async Task AssertRecordAtVersionAsync(
        NpgsqlConnection db, Guid accountId, Guid id, int schemaVersion, string expectedPayload)
    {
        var row = await db.QuerySingleAsync<(int schema_version, string payload)>(
            "SELECT schema_version, payload::text AS payload FROM records WHERE account_id = @accountId AND id = @id",
            new { accountId, id });

        Assert.Equal(schemaVersion, row.schema_version);

        var stored = JsonNode.Parse(row.payload);
        var expected = JsonNode.Parse(expectedPayload);
        Assert.True(
            JsonNode.DeepEquals(stored, expected),
            $"Unexpected payload for record {id}: expected {expected} but stored {stored}.");
    }
}
