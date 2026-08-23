using Npgsql;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests;

/// <summary>
/// The payload schema registry lives in the database, not in code
/// (docs/SYNC.md "The schema registry lives in the database"). Applying the
/// migrations must seed <c>payload_schemas</c> from the canonical schema files,
/// and the stored JSON must be byte-identical (in canonical jsonb form) to the
/// source files. Real Postgres because SQL is the subject.
/// </summary>
public class PayloadRegistryTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public PayloadRegistryTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task ApplyingMigrations_SeedsEveryRegisteredEntityAtVersionOne()
    {
        await using var db = await NewMigratedDbAsync();

        var rows = await db.QueryAsync<(string entity_type, int schema_version)>(
            "SELECT entity_type, schema_version FROM payload_schemas ORDER BY entity_type");

        var registered = rows.ToList();
        Assert.Equal(11, registered.Count);

        var expectedEntities = Directory.EnumerateFiles(DocPaths.SchemasV1, "*.schema.json")
            .Select(f => Path.GetFileName(f)[..^".schema.json".Length])
            .OrderBy(e => e, StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(expectedEntities, registered.Select(r => r.entity_type).ToArray());
        Assert.All(registered, r => Assert.Equal(1, r.schema_version));
    }

    [SkippableFact]
    public async Task StoredJson_MatchesTheSourceFile_ByteForByteInCanonicalForm()
    {
        await using var db = await NewMigratedDbAsync();

        foreach (var schemaFile in Directory.EnumerateFiles(DocPaths.SchemasV1, "*.schema.json"))
        {
            var entityType = Path.GetFileName(schemaFile)[..^".schema.json".Length];
            var fileJson = File.ReadAllText(schemaFile);

            var stored = await db.QuerySingleAsync<string>(
                "SELECT json_schema::text FROM payload_schemas WHERE entity_type = @entityType AND schema_version = 1",
                new { entityType });

            // jsonb normalizes whitespace/key order, so byte-for-byte means
            // equality of the canonical jsonb serialization of both sides.
            var canonicalFile = await db.QuerySingleAsync<string>("SELECT @fileJson::jsonb::text", new { fileJson });

            Assert.True(
                string.Equals(stored, canonicalFile, StringComparison.Ordinal),
                $"Stored schema for '{entityType}' differs from the canonical form of its source file.");
        }
    }

    [SkippableFact]
    public async Task PayloadMigrations_StartsEmpty()
    {
        await using var db = await NewMigratedDbAsync();

        var count = await db.QuerySingleAsync<int>("SELECT count(*) FROM payload_migrations");
        Assert.Equal(0, count);
    }

    [SkippableFact]
    public async Task Records_HasSchemaVersionColumn_DefaultingToOne()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = Guid.NewGuid();
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@id, @email)",
            new { id = accountId, email = $"registry-{Guid.NewGuid():N}@example.com" });
        var recordId = Guid.NewGuid();

        // Insert without schema_version: the DEFAULT must supply 1.
        await db.ExecuteAsync(
            """
            INSERT INTO records (account_id, id, entity_type, scn, payload, client_updated_at)
            VALUES (@accountId, @id, 'vehicle', 1, '{}'::jsonb, now())
            """,
            new { accountId, id = recordId });

        var schemaVersion = await db.QuerySingleAsync<int>(
            "SELECT schema_version FROM records WHERE account_id = @accountId AND id = @id",
            new { accountId, id = recordId });

        Assert.Equal(1, schemaVersion);
    }

    [SkippableFact]
    public async Task Rollback_DropsThePayloadContractTables()
    {
        await using var db = await NewMigratedDbAsync();

        await SchemaMigrator.RollbackAsync(db);

        var tables = await db.QueryAsync<string>(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public'");
        Assert.DoesNotContain("payload_schemas", tables);
        Assert.DoesNotContain("payload_migrations", tables);

        var hasColumn = await db.QuerySingleAsync<int>(
            """
            SELECT count(*) FROM information_schema.columns
            WHERE table_name = 'records' AND column_name = 'schema_version'
            """);
        Assert.Equal(0, hasColumn);
    }

    private async Task<NpgsqlConnection> NewMigratedDbAsync()
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }
}
