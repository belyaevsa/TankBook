using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Npgsql;
using Tankbook.Api.Account;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;

namespace Tankbook.Api.Tests.Account;

/// <summary>
/// L2 tests for the account & devices surface and the grace purge job (docs/API.md
/// "Account & devices", docs/SYNC.md "Offline & failure behavior") against real
/// Postgres via Testcontainers. The idToken verifier is the test signer and
/// IBlobStorage is a recording double - the bearer middleware, the repositories,
/// the tombstone/purge logic and the HTTP surface are all real; only the external
/// identity provider and the object store are faked (docs/TESTING.md "mock the
/// boundary").
/// </summary>
public class AccountEndpointTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public AccountEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- 1. Deletion is a tombstone, not a delete --------------------------

    [SkippableFact]
    public async Task DeleteAccount_Tombstones_AndDeletesNoRecordsSynchronously()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "tomb-sub", "tomb@example.com");

        await InsertRecordAsync(app, accountId, scn: 1);
        await InsertRecordAsync(app, accountId, scn: 2);

        var response = await DeleteAccountAsync(app.Client, token);
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // The "local data stays local" guarantee's server half: the records are
        // still there, and the account is marked deleted rather than removed.
        Assert.Equal(2, await app.CountAsync("records", "account_id = @p", new { p = accountId }));
        Assert.Equal(1, await app.CountAsync("accounts", "id = @p", new { p = accountId }));
        Assert.True(await app.ScalarAsync<bool>("SELECT deleted_at IS NOT NULL FROM accounts WHERE id = @p", new { p = accountId }));
    }

    // ---- 2. Every device gets 410 after account deletion -------------------

    [SkippableFact]
    public async Task DeleteAccount_EveryDeviceGets410_ThroughTheRevokedPath()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token1, accountId, device1) = await CreateSessionAsync(app, signer, "del-sub", "del@example.com", "iPhone");
        var (token2, _, device2) = await CreateSessionAsync(app, signer, "del-sub", "del@example.com", "iPad");

        Assert.Equal(accountId, await app.ScalarAsync<Guid>("SELECT account_id FROM devices WHERE id = @p", new { p = device2 }));
        Assert.NotEqual(device1, device2);

        var deleted = await DeleteAccountAsync(app.Client, token1);
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);

        // Both devices pull gets 410 through the same IsDeviceActiveAsync path a
        // revoked device takes (accounts.deleted_at makes the account inactive).
        Assert.Equal(HttpStatusCode.Gone, (await PullAsync(app.Client, token1)).StatusCode);
        Assert.Equal(HttpStatusCode.Gone, (await PullAsync(app.Client, token2)).StatusCode);
    }

    // ---- 3. Revoking ONE device leaves the others working ------------------

    [SkippableFact]
    public async Task DeleteDevice_RevokesOnlyThatDevice_AndDeletesNoRecords()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token1, accountId, device1) = await CreateSessionAsync(app, signer, "rev-sub", "rev@example.com", "iPhone");
        var (token2, _, device2) = await CreateSessionAsync(app, signer, "rev-sub", "rev@example.com", "iPad");

        await InsertRecordAsync(app, accountId, scn: 1);

        var revoke = await DeleteDeviceAsync(app.Client, token1, device1);
        Assert.Equal(HttpStatusCode.NoContent, revoke.StatusCode);

        Assert.Equal(HttpStatusCode.Gone, (await PullAsync(app.Client, token1)).StatusCode);

        // The sibling device still works and the record is untouched.
        var live = await PullAsync(app.Client, token2);
        Assert.Equal(HttpStatusCode.OK, live.StatusCode);
        Assert.Equal(1, await app.CountAsync("records", "account_id = @p", new { p = accountId }));

        Assert.True(await app.ScalarAsync<bool>("SELECT revoked_at IS NOT NULL FROM devices WHERE id = @p", new { p = device1 }));
        Assert.False(await app.ScalarAsync<bool>("SELECT revoked_at IS NOT NULL FROM devices WHERE id = @p", new { p = device2 }));
    }

    // ---- 4. The purge fires only past the grace period ---------------------

    [SkippableFact]
    public async Task PurgeDueAccounts_DeletesOnlyAccountsPastGrace()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage, deletionGraceDays: 1);
        var (_, accountA, _) = await CreateSessionAsync(app, signer, "purge-a", "a@example.com");
        var (_, accountB, _) = await CreateSessionAsync(app, signer, "purge-b", "b@example.com");

        var blobA = Sha('a');
        var blobB = Sha('b');
        await InsertBlobAsync(app, accountA, blobA, storage);
        await InsertBlobAsync(app, accountB, blobB, storage);
        await InsertRecordAsync(app, accountA, scn: 1);
        await InsertRecordAsync(app, accountB, scn: 1);

        // A tombstoned just now (within the 1-day window); B tombstoned 2 days ago (past it).
        await app.Db.ExecuteAsync("UPDATE accounts SET deleted_at = now() WHERE id = @p", new { p = accountA });
        await app.Db.ExecuteAsync("UPDATE accounts SET deleted_at = now() - interval '2 days' WHERE id = @p", new { p = accountB });

        using var scope = app.Services.CreateScope();
        var purge = scope.ServiceProvider.GetRequiredService<AccountPurgeService>();
        var result = await purge.PurgeDueAccountsAsync(CancellationToken.None);

        Assert.Equal(1, result.AccountsPurged);

        // The surviving case is the half that matters: A's records and blob are intact.
        Assert.Equal(1, await app.CountAsync("records", "account_id = @p", new { p = accountA }));
        Assert.Equal(1, await app.CountAsync("blobs", "account_id = @p", new { p = accountA }));
        Assert.True(storage.Objects.ContainsKey(BlobKeys.Key(accountA, blobA)));

        // B is fully purged: records, blob index and the storage object are gone.
        Assert.Equal(0, await app.CountAsync("records", "account_id = @p", new { p = accountB }));
        Assert.Equal(0, await app.CountAsync("blobs", "account_id = @p", new { p = accountB }));
        Assert.Equal(0, await app.CountAsync("accounts", "id = @p", new { p = accountB }));
        Assert.False(storage.Objects.ContainsKey(BlobKeys.Key(accountB, blobB)));
    }

    // ---- 5. Cross-account device access is 404 and changes nothing ---------

    [SkippableFact]
    public async Task DeviceAccess_CrossAccount_Returns404_AndLeavesTargetUntouched()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (tokenA, _, deviceA) = await CreateSessionAsync(app, signer, "owner", "owner@example.com");
        var (tokenB, _, _) = await CreateSessionAsync(app, signer, "intruder", "intruder@example.com");

        // Foreign push-token write -> 404, and A's row still holds no token.
        var setToken = await SetPushTokenAsync(app.Client, tokenB, deviceA, new { apnsToken = "foreign-token" });
        Assert.Equal(HttpStatusCode.NotFound, setToken.StatusCode);
        Assert.Null(await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceA }));

        // Foreign revoke -> 404, and A's device is still active.
        var revoke = await DeleteDeviceAsync(app.Client, tokenB, deviceA);
        Assert.Equal(HttpStatusCode.NotFound, revoke.StatusCode);
        Assert.False(await app.ScalarAsync<bool>("SELECT revoked_at IS NOT NULL FROM devices WHERE id = @p", new { p = deviceA }));

        // Sanity: the real owner can still set the token (A's row is healthy).
        var own = await SetPushTokenAsync(app.Client, tokenA, deviceA, new { apnsToken = "real-token" });
        Assert.Equal(HttpStatusCode.NoContent, own.StatusCode);
        Assert.Equal("real-token", await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceA }));
    }

    // ---- 6. Push token round-trip and clearing -----------------------------

    [SkippableFact]
    public async Task PushToken_SetThenClear_LeavesEmptyRowNotStaleToken()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token, _, deviceId) = await CreateSessionAsync(app, signer, "push-sub", "push@example.com");

        var set = await SetPushTokenAsync(app.Client, token, deviceId, new { apnsToken = "apns-token-abc" });
        Assert.Equal(HttpStatusCode.NoContent, set.StatusCode);
        Assert.Equal("apns-token-abc", await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceId }));

        // Clearing is expressible: an explicit null empties the row.
        var clear = await SetPushTokenAsync(app.Client, token, deviceId, new { apnsToken = (string?)null });
        Assert.Equal(HttpStatusCode.NoContent, clear.StatusCode);
        Assert.Null(await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceId }));

        // An absent token key empties the row too.
        await SetPushTokenAsync(app.Client, token, deviceId, new { apnsToken = "apns-token-def" });
        var clearAbsent = await SetPushTokenAsync(app.Client, token, deviceId, new { });
        Assert.Equal(HttpStatusCode.NoContent, clearAbsent.StatusCode);
        Assert.Null(await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceId }));
    }

    // ---- 7. GET /account/devices lists only this account's devices ---------

    [SkippableFact]
    public async Task GetDevices_ListsOnlyThisAccount_AndMarksRevoked()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (tokenA, _, deviceA1) = await CreateSessionAsync(app, signer, "list-a", "a@example.com", "iPhone");
        var (tokenA2, _, deviceA2) = await CreateSessionAsync(app, signer, "list-a", "a@example.com", "iPad");
        var (tokenB, _, deviceB) = await CreateSessionAsync(app, signer, "list-b", "b@example.com", "Pixel");

        // Revoke A's first device, so the list must show one revoked and one active.
        Assert.Equal(HttpStatusCode.NoContent, (await DeleteDeviceAsync(app.Client, tokenA2, deviceA1)).StatusCode);

        var devicesA = await GetDevicesAsync(app.Client, tokenA2);
        Assert.Equal(HttpStatusCode.OK, devicesA.StatusCode);
        var listA = ParseDevices(await devicesA.Content.ReadAsStringAsync());
        Assert.Equal(2, listA.Count);
        Assert.DoesNotContain(listA, d => d.Id == deviceB);

        var a1 = listA.Single(d => d.Id == deviceA1);
        Assert.True(a1.Revoked);
        var a2 = listA.Single(d => d.Id == deviceA2);
        Assert.False(a2.Revoked);

        // Account B sees only its own device.
        var devicesB = await GetDevicesAsync(app.Client, tokenB);
        var listB = ParseDevices(await devicesB.Content.ReadAsStringAsync());
        Assert.Equal([deviceB], listB.Select(d => d.Id).ToArray());
    }

    // ---- 8. No token, push token or email reaches a log --------------------

    [SkippableFact]
    public async Task AccountFlow_NoTokenPushTokenOrEmailReachesALog()
    {
        const string secretEmail = "log-secret-email@example.com";
        const string secretPushToken = "apns-secret-token-7f3a";

        var signer = new TestIdTokenSigner();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, new RecordingBlobStorage(), writer);

        var (accessToken, _, deviceId) = await CreateSessionAsync(app, signer, "log-sub", secretEmail);

        var set = await SetPushTokenAsync(app.Client, accessToken, deviceId, new { apnsToken = secretPushToken });
        Assert.Equal(HttpStatusCode.NoContent, set.StatusCode);

        var deleted = await DeleteAccountAsync(app.Client, accessToken);
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);

        var all = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The pipeline captured the account events (not an empty sweep).
        Assert.Contains(lines, l => l.Contains("auth.session", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains("account.delete", StringComparison.Ordinal));

        // Hard rule 12: the token, push token and email never reach any log line.
        Assert.DoesNotContain(accessToken, all, StringComparison.Ordinal);
        Assert.DoesNotContain(secretPushToken, all, StringComparison.Ordinal);
        Assert.DoesNotContain(secretEmail, all, StringComparison.Ordinal);
    }

    // ---- 9. The purge timer never runs inside a test host ------------------

    [SkippableFact]
    public async Task PurgeTimer_IsNotRegisteredInTheTestHost()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());

        // Tests drive AccountPurgeService.PurgeDueAccountsAsync directly, never
        // the clock (P4.3 declined to add a timer for exactly this reason).
        Assert.DoesNotContain(app.Services.GetServices<IHostedService>(), h => h is AccountPurgeHostedService);
    }

    // ---- helpers -----------------------------------------------------------

    private static string Sha(char c) => new(c, 64);

    private async Task<TestApp> StartAsync(
        TestIdTokenSigner signer,
        RecordingBlobStorage storage,
        InMemoryLogWriter? writer = null,
        int? deletionGraceDays = null)
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        var connectionString = db.ConnectionString;

        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:Postgres", connectionString);
                if (deletionGraceDays is not null)
                {
                    b.UseSetting("Account:DeletionGraceDays", deletionGraceDays.Value.ToString());
                }

                b.ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                    services.Replace(ServiceDescriptor.Singleton<IBlobStorage>(storage));
                    if (writer is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton<ILogWriter>(writer));
                    }
                });
            });

        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        return new TestApp(factory, client, db, signer, storage);
    }

    private static async Task<(string AccessToken, Guid AccountId, Guid DeviceId)> CreateSessionAsync(
        TestApp app,
        TestIdTokenSigner signer,
        string subject,
        string email,
        string deviceName = "iPhone")
    {
        var idToken = signer.Mint("apple", subject, email);
        var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken,
            device = new { name = deviceName, platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionResponse>();
        return (body!.AccessToken, body.AccountId, body.DeviceId);
    }

    private static async Task InsertRecordAsync(TestApp app, Guid accountId, long scn)
    {
        await app.Db.ExecuteAsync(
            """
            INSERT INTO records (account_id, id, entity_type, schema_version, scn, payload, client_updated_at, deleted)
            VALUES (@a, @id, 'vehicle', 1, @scn, '{}'::jsonb, now(), false)
            """,
            new { a = accountId, id = Guid.NewGuid(), scn });
    }

    private static async Task InsertBlobAsync(TestApp app, Guid accountId, string sha256, RecordingBlobStorage storage)
    {
        var key = BlobKeys.Key(accountId, sha256);
        storage.Put(key, 1000);
        await app.Db.ExecuteAsync(
            "INSERT INTO blobs (account_id, sha256, size_bytes, storage_ref) VALUES (@a, @s, 1000, @r)",
            new { a = accountId, s = sha256, r = key });
    }

    private static async Task<HttpResponseMessage> GetDevicesAsync(HttpClient client, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/account/devices");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> SetPushTokenAsync(HttpClient client, string token, Guid deviceId, object body)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/v1/account/devices/{deviceId}/push-token");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(body);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> DeleteDeviceAsync(HttpClient client, string token, Guid deviceId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, $"/v1/account/devices/{deviceId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> DeleteAccountAsync(HttpClient client, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, "/v1/account");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> PullAsync(HttpClient client, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/sync/pull?since=0&limit=500");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static List<AccountDevice> ParseDevices(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("devices").EnumerateArray()
            .Select(d => new AccountDevice(
                Guid.Parse(d.GetProperty("id").GetString()!),
                d.GetProperty("name").GetString()!,
                d.GetProperty("platform").GetString()!,
                d.GetProperty("lastSeenAt").GetDateTimeOffset(),
                d.GetProperty("revoked").GetBoolean()))
            .ToList();
    }

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;
        private readonly HttpClient _client;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db, TestIdTokenSigner signer, RecordingBlobStorage storage)
        {
            _factory = factory;
            _client = client;
            Db = db;
            Signer = signer;
            Storage = storage;
        }

        public HttpClient Client => _client;

        public NpgsqlConnection Db { get; }

        public TestIdTokenSigner Signer { get; }

        public RecordingBlobStorage Storage { get; }

        public IServiceProvider Services => _factory.Services;

        public Task<int> CountAsync(string table, string? where = null, object? param = null)
            => Db.QuerySingleAsync<int>(
                $"SELECT count(*) FROM {table}" + (where is null ? "" : " WHERE " + where),
                param ?? new { });

        public Task<T> ScalarAsync<T>(string sql, object? param = null)
            => Db.QuerySingleAsync<T>(sql, param ?? new { });

        public async ValueTask DisposeAsync()
        {
            _client.Dispose();
            await Db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
