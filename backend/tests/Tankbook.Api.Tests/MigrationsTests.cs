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
        "catalog_pack_state",
        "import_parses",
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
        Assert.Equal(12, applied.Single());

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
        Assert.DoesNotContain("catalog_pack_state", tables);
        Assert.DoesNotContain("import_parses", tables);

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
    public async Task Migration009_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The correction-path columns and the partial unique index exist after apply.
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.columns WHERE table_name = 'exchange_rates' AND column_name = 'deleted_at'"));
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.columns WHERE table_name = 'exchange_rates' AND column_name = 'id'"));
        Assert.Equal(1, await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'uq_exchange_rates_active'"));

        // The primary key now sits on the surrogate id, not (date, base, quote).
        var pkColumns = await db.QueryAsync<string>(
            """
            SELECT a.attname
            FROM pg_index i
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
            WHERE i.indrelid = 'exchange_rates'::regclass AND i.indisprimary
            ORDER BY a.attnum
            """);
        Assert.Equal(new[] { "id" }, pkColumns.ToArray());

        await SchemaMigrator.RollbackAsync(db);

        // And both are gone after rollback (the table itself is dropped by 001's
        // rollback, so the columns and index vanish with it).
        Assert.Equal(0, await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'uq_exchange_rates_active'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '009'"));
    }

    [SkippableFact]
    public async Task Migration010_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The LLM tier column exists after apply, and a fresh account defaults
        // to the free tier (so an account never gets a paid allowance unprompted).
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.columns WHERE table_name = 'accounts' AND column_name = 'llm_tier'"));
        await db.ExecuteAsync("INSERT INTO accounts (id, email) VALUES (gen_random_uuid(), 'tier@example.com')");
        Assert.Equal("free", await db.QuerySingleAsync<string>("SELECT llm_tier FROM accounts WHERE email = 'tier@example.com'"));

        await SchemaMigrator.RollbackAsync(db);

        // And it is gone after rollback.
        Assert.Equal(0, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.columns WHERE table_name = 'accounts' AND column_name = 'llm_tier'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '010'"));
    }

    [SkippableFact]
    public async Task Migration011_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The singleton pack-state row exists after apply and is seeded from the
        // (empty) catalog, so a fresh table reads back pack version 0.
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.tables WHERE table_name = 'catalog_pack_state'"));
        var (singleton, seeded) = await db.QuerySingleAsync<(int, int)>(
            "SELECT singleton, pack_version FROM catalog_pack_state");
        Assert.Equal(1, singleton);
        Assert.Equal(0, seeded);

        // The CHECK constraint keeps it a true singleton: a second row is refused.
        await Assert.ThrowsAsync<Npgsql.PostgresException>(() => db.ExecuteAsync(
            "INSERT INTO catalog_pack_state (singleton, pack_version) VALUES (2, 5)"));
        Assert.Equal(1, await db.QuerySingleAsync<int>("SELECT count(*) FROM catalog_pack_state"));

        await SchemaMigrator.RollbackAsync(db);

        // And the table is gone after rollback.
        Assert.Equal(0, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.tables WHERE table_name = 'catalog_pack_state'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '011'"));
    }

    [SkippableFact]
    public async Task Migration012_AppliesAndRollsBack()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();

        await SchemaMigrator.ApplyPendingAsync(db);

        // The import-parse index exists after apply, with the purge-scan index
        // on created_at and the account-deletion index on account_id.
        Assert.Equal(1, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.tables WHERE table_name = 'import_parses'"));
        Assert.Equal(1L, await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_import_parses_created_at'"));
        Assert.Equal(1L, await db.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_import_parses_account'"));

        // A row round-trips, including a NULL account_id (the signed-out shape).
        await db.ExecuteAsync(
            "INSERT INTO import_parses (id, account_id, device_id, format, file_kind, file_key, result_key, rows_read, candidate_count, unparsed_count) VALUES (gen_random_uuid(), NULL, gen_random_uuid(), 'mfm', 'fuel', 'k/original', 'k/result.json', 513, 513, 0)");
        Assert.Equal(1, await db.QuerySingleAsync<int>("SELECT count(*) FROM import_parses"));

        await SchemaMigrator.RollbackAsync(db);

        // And the table and indexes are gone after rollback.
        Assert.Equal(0, await db.QuerySingleAsync<int>(
            "SELECT count(*) FROM information_schema.tables WHERE table_name = 'import_parses'"));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM schema_migrations WHERE version = '012'"));
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
