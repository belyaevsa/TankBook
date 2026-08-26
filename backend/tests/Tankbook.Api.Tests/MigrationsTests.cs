using Npgsql;
using Tankbook.Api.Config;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests;

public class MigrationsTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public MigrationsTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    public static readonly string[] ExpectedTables =
    {
        "accounts",
        "devices",
        "records",
        "account_seq",
        "blobs",
        "llm_usage",
        "exchange_rates",
        "vehicle_catalog",
        "feedback",
        "payload_schemas",
        "payload_migrations",
        "config_documents",
        "refresh_tokens",
        "blob_pending",
    };

    [SkippableFact]
    public async Task ApplyMigrations_CreatesEveryExpectedTable()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        var tables = await GetPublicTablesAsync(db);
        var expected = ExpectedTables.Append("schema_migrations").OrderBy(t => t, StringComparer.Ordinal).ToArray();
        Assert.Equal(expected, tables.OrderBy(t => t, StringComparer.Ordinal).ToArray());
    }

    [SkippableFact]
    public async Task ApplyMigrations_Twice_IsANoOp()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);
        await SchemaMigrator.ApplyPendingAsync(db);

        var applied = await db.QueryAsync<int>("SELECT count(*) FROM schema_migrations");
        Assert.Equal(8, applied.Single());

        var tables = await GetPublicTablesAsync(db);
        var expected = ExpectedTables.Append("schema_migrations").OrderBy(t => t, StringComparer.Ordinal).ToArray();
        Assert.Equal(expected, tables.OrderBy(t => t, StringComparer.Ordinal).ToArray());
    }

    [SkippableFact]
    public async Task RollbackMigrations_DropsAllTables()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);
        await SchemaMigrator.RollbackAsync(db);

        var tables = await GetPublicTablesAsync(db);
        Assert.DoesNotContain("accounts", tables);
        Assert.DoesNotContain("devices", tables);
        Assert.DoesNotContain("records", tables);
        Assert.DoesNotContain("account_seq", tables);
        Assert.DoesNotContain("blobs", tables);
        Assert.DoesNotContain("llm_usage", tables);
        Assert.DoesNotContain("exchange_rates", tables);
        Assert.DoesNotContain("vehicle_catalog", tables);
        Assert.DoesNotContain("feedback", tables);
        Assert.DoesNotContain("payload_schemas", tables);
        Assert.DoesNotContain("payload_migrations", tables);
        Assert.DoesNotContain("config_documents", tables);
        Assert.DoesNotContain("refresh_tokens", tables);
        Assert.DoesNotContain("blob_pending", tables);

        var remaining = await db.QueryAsync<int>("SELECT count(*) FROM schema_migrations");
        Assert.Equal(0, remaining.Single());
    }

    [SkippableFact]
    public async Task Migration006_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The sweep index and the pending-upload table exist after apply.
        var index = await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_blobs_account_created'");
        Assert.Equal(1L, index);
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.tables WHERE table_name = 'blob_pending'"));

        await SchemaMigrator.RollbackAsync(db);

        // And both are gone after rollback.
        var indexAfter = await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_blobs_account_created'");
        Assert.Equal(0L, indexAfter);
        Assert.Equal(0, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.tables WHERE table_name = 'blob_pending'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '006'"));
    }

    [SkippableFact]
    public async Task Migration007_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The purge-scan index exists after apply.
        Assert.Equal(1L, await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_accounts_deleted_at'"));

        await SchemaMigrator.RollbackAsync(db);

        // And is gone after rollback.
        Assert.Equal(0L, await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_accounts_deleted_at'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '007'"));
    }

    [SkippableFact]
    public async Task Migration008_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The nudge-throttle column exists after apply.
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.columns WHERE table_name = 'devices' AND column_name = 'last_nudged_at'"));

        await SchemaMigrator.RollbackAsync(db);

        // And is gone after rollback.
        Assert.Equal(0, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.columns WHERE table_name = 'devices' AND column_name = 'last_nudged_at'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '008'"));
    }

    [SkippableFact]
    public async Task Migration003_SeedsASchemaValidBaselineVersionOne()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // Migration 003 seeds version 1 with bundled-equivalent defaults. The
        // seeded document must stay schema-valid: ConfigBaselineSeeder refuses
        // to sign a document that violates the schema, so a drift here would
        // leave GET /config serving an unsigned baseline that clients reject.
        var (version, document) = await db.QuerySingleAsync<(int, string)>(
            "SELECT version, document::text FROM config_documents WHERE version = 1");
        Assert.Equal(1, version);
        Assert.Empty(new ConfigSchemaValidator().Validate(document));
    }

    private static async Task<List<string>> GetPublicTablesAsync(NpgsqlConnection db)
    {
        var rows = await db.QueryAsync<string>(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public'");
        return rows.ToList();
    }
}
