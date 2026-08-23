using Npgsql;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests;

public class ConstraintsTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public ConstraintsTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task AppleSub_IsUnique_AcrossAccounts()
    {
        await using var db = await NewMigratedDbAsync();
        await InsertAccountAsync(db, Guid.NewGuid(), appleSub: "apple-1");

        var ex = await Assert.ThrowsAsync<PostgresException>(
            () => InsertAccountAsync(db, Guid.NewGuid(), appleSub: "apple-1"));
        Assert.Equal("23505", ex.SqlState);
    }

    [SkippableFact]
    public async Task GoogleSub_IsUnique_AcrossAccounts()
    {
        await using var db = await NewMigratedDbAsync();
        await InsertAccountAsync(db, Guid.NewGuid(), googleSub: "google-1");

        var ex = await Assert.ThrowsAsync<PostgresException>(
            () => InsertAccountAsync(db, Guid.NewGuid(), googleSub: "google-1"));
        Assert.Equal("23505", ex.SqlState);
    }

    [SkippableFact]
    public async Task AppleSubAndGoogleSub_CanBothBeNull_AndRepeat()
    {
        await using var db = await NewMigratedDbAsync();
        await InsertAccountAsync(db, Guid.NewGuid(), appleSub: null, googleSub: null);
        await InsertAccountAsync(db, Guid.NewGuid(), appleSub: null, googleSub: null);
    }

    [SkippableFact]
    public async Task RecordsPrimaryKey_IsAccountAndId()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = Guid.NewGuid();
        await InsertAccountAsync(db, accountId);
        var recordId = Guid.NewGuid();

        await InsertRecordAsync(db, accountId, recordId, scn: 1);

        var ex = await Assert.ThrowsAsync<PostgresException>(
            () => InsertRecordAsync(db, accountId, recordId, scn: 2));
        Assert.Equal("23505", ex.SqlState);
    }

    [SkippableFact]
    public async Task RecordsKey_AllowsSameIdUnderDifferentAccounts()
    {
        await using var db = await NewMigratedDbAsync();
        var recordId = Guid.NewGuid();
        var accountA = Guid.NewGuid();
        var accountB = Guid.NewGuid();
        await InsertAccountAsync(db, accountA);
        await InsertAccountAsync(db, accountB);

        await InsertRecordAsync(db, accountA, recordId, scn: 1);
        await InsertRecordAsync(db, accountB, recordId, scn: 1);
    }

    [SkippableFact]
    public async Task DeletingAccount_CascadesToRecordsBlobsDevicesAndSeq()
    {
        await using var db = await NewMigratedDbAsync();
        var accountId = Guid.NewGuid();
        await InsertAccountAsync(db, accountId);
        await InsertRecordAsync(db, accountId, Guid.NewGuid(), scn: 1);
        await InsertBlobAsync(db, accountId, "deadbeef");
        await InsertDeviceAsync(db, accountId);

        await db.ExecuteAsync("DELETE FROM accounts WHERE id = @id", new { id = accountId });

        Assert.Equal(0, await CountAsync(db, "records", accountId));
        Assert.Equal(0, await CountAsync(db, "blobs", accountId));
        Assert.Equal(0, await CountAsync(db, "devices", accountId));
        Assert.Equal(0, await CountAsync(db, "account_seq", accountId));
    }

    [SkippableFact]
    public async Task Feedback_MayExistWithoutAnAccount()
    {
        await using var db = await NewMigratedDbAsync();

        await db.ExecuteAsync(
            "INSERT INTO feedback (id, category, text) VALUES (@id, 'problem', 'hello')",
            new { id = Guid.NewGuid() });
    }

    private async Task<NpgsqlConnection> NewMigratedDbAsync()
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static async Task InsertAccountAsync(
        NpgsqlConnection db,
        Guid id,
        string? appleSub = null,
        string? googleSub = null)
    {
        await db.ExecuteAsync(
            "INSERT INTO accounts (id, apple_sub, google_sub, email) VALUES (@id, @appleSub, @googleSub, @email)",
            new { id, appleSub, googleSub, email = $"user-{Guid.NewGuid():N}@example.com" });
    }

    private static async Task InsertRecordAsync(NpgsqlConnection db, Guid accountId, Guid id, long scn)
    {
        await db.ExecuteAsync(
            """
            INSERT INTO records (account_id, id, entity_type, scn, payload, client_updated_at)
            VALUES (@accountId, @id, 'vehicle', @scn, '{}'::jsonb, now())
            """,
            new { accountId, id, scn });
    }

    private static async Task InsertBlobAsync(NpgsqlConnection db, Guid accountId, string sha256)
    {
        await db.ExecuteAsync(
            "INSERT INTO blobs (account_id, sha256, size_bytes, storage_ref) VALUES (@accountId, @sha256, 16, @sha256)",
            new { accountId, sha256 });
    }

    private static async Task InsertDeviceAsync(NpgsqlConnection db, Guid accountId)
    {
        await db.ExecuteAsync(
            "INSERT INTO devices (id, account_id, name, platform) VALUES (@id, @accountId, 'iPhone', 'ios')",
            new { id = Guid.NewGuid(), accountId });
    }

    private static async Task<int> CountAsync(NpgsqlConnection db, string table, Guid accountId)
    {
        return await db.QuerySingleAsync<int>(
            $"SELECT count(*) FROM {table} WHERE account_id = @accountId",
            new { accountId });
    }
}
