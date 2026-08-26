using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Tankbook.Api.Auth;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests.Auth;

/// <summary>
/// L2 tests for the auth endpoints (docs/API.md Auth) against real Postgres via
/// Testcontainers. The idToken verifier is the test signer - the auth pipeline,
/// the database, and the HTTP surface are all real; only the external identity
/// providers are faked (docs/TESTING.md "mock the boundary").
/// </summary>
public class AuthEndpointTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public AuthEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task CreateSession_ReturnsTokenPair_AndPersistsHashedRefreshToken()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var idToken = signer.Mint("apple", "apple-sub-1", "driver@example.com");

        var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken,
            device = new { name = "iPhone", platform = "ios" },
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionResponse>();
        Assert.NotNull(body);
        Assert.False(string.IsNullOrWhiteSpace(body.AccessToken));
        Assert.False(string.IsNullOrWhiteSpace(body.RefreshToken));
        Assert.NotEqual(Guid.Empty, body.AccountId);
        Assert.NotEqual(Guid.Empty, body.DeviceId);

        // The account and device were created, and the refresh token is stored
        // as a hash, never the value (docs/SECURITY.md).
        Assert.Equal(1, await app.CountAsync("accounts", "apple_sub = 'apple-sub-1'"));
        Assert.Equal("driver@example.com", await app.ScalarAsync<string>("SELECT email FROM accounts WHERE apple_sub = 'apple-sub-1'"));
        Assert.Equal(1, await app.CountAsync("devices", "account_id = @p", new { p = body.AccountId }));

        var storedHash = await app.ScalarAsync<string>("SELECT token_hash FROM refresh_tokens WHERE device_id = @p", new { p = body.DeviceId });
        Assert.Equal(RefreshTokenHasher.Hash(body.RefreshToken), storedHash);
        Assert.NotEqual(body.RefreshToken, storedHash);
        Assert.DoesNotContain(body.RefreshToken, storedHash, StringComparison.Ordinal);
    }

    [SkippableFact]
    public async Task CreateSession_GarbageAndExpiredTokens_Return401WithoutCreatingAnAccount()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);

        var garbage = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken = "garbage.token.value",
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.Unauthorized, garbage.StatusCode);

        var expiredIdToken = signer.MintExpired("apple", "apple-sub-2", "expired@example.com");
        var expired = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken = expiredIdToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.Unauthorized, expired.StatusCode);

        Assert.Equal(0, await app.CountAsync("accounts"));
    }

    [SkippableFact]
    public async Task ConcurrentFirstSignIn_CreatesExactlyOneAccount()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var idToken = signer.Mint("apple", "shared-sub", "shared@example.com");

        const int requests = 8;
        var tasks = Enumerable.Range(0, requests)
            .Select(_ => app.Client.PostAsJsonAsync("/v1/auth/session", new
            {
                provider = "apple",
                idToken,
                device = new { name = "iPhone", platform = "ios" },
            }))
            .ToArray();

        var responses = await Task.WhenAll(tasks);

        Assert.All(responses, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
        Assert.Equal(1, await app.CountAsync("accounts"));
        Assert.Equal(requests, await app.CountAsync("devices"));
        Assert.Equal(requests, await app.CountAsync("refresh_tokens"));
    }

    [SkippableFact]
    public async Task Refresh_RotatesToken_AndTheOldTokenStopsWorking()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (_, refresh1, _, _) = await CreateSessionAsync(app, signer, "apple", "rot-sub", "rot@example.com");

        var rotated = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        var pair2 = await rotated.Content.ReadFromJsonAsync<RefreshResponse>();
        Assert.False(string.IsNullOrWhiteSpace(pair2!.AccessToken));
        Assert.NotEqual(refresh1, pair2.RefreshToken);

        var oldRejected = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.Unauthorized, oldRejected.StatusCode);
    }

    [SkippableFact]
    public async Task Refresh_RotatingTwice_LeavesEarlierTokensDead()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (_, refresh1, _, _) = await CreateSessionAsync(app, signer, "apple", "rot2-sub", "rot2@example.com");

        var first = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var refresh2 = (await first.Content.ReadFromJsonAsync<RefreshResponse>())!.RefreshToken;

        var second = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh2 });
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.NotEqual(refresh2, (await second.Content.ReadFromJsonAsync<RefreshResponse>())!.RefreshToken);

        // Both earlier tokens are dead after the second rotation.
        var refresh2Rejected = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh2 });
        Assert.Equal(HttpStatusCode.Unauthorized, refresh2Rejected.StatusCode);
        var refresh1Rejected = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.Unauthorized, refresh1Rejected.StatusCode);
    }

    [SkippableFact]
    public async Task Refresh_ReuseRevokesTheWholeChain()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (_, refresh1, _, _) = await CreateSessionAsync(app, signer, "apple", "reuse-sub", "reuse@example.com");

        var first = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var refresh2 = (await first.Content.ReadFromJsonAsync<RefreshResponse>())!.RefreshToken;

        // Reuse: presenting the already-rotated token again.
        var reuse = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.Unauthorized, reuse.StatusCode);

        // The security-relevant half: the chain's current token is now dead too.
        var currentDead = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh2 });
        Assert.Equal(HttpStatusCode.Unauthorized, currentDead.StatusCode);

        // Nothing deleted; both rows remain and both are revoked.
        Assert.Equal(2, await app.CountAsync("refresh_tokens"));
        Assert.Equal(2, await app.CountAsync("refresh_tokens", "revoked_at IS NOT NULL"));
    }

    [SkippableFact]
    public async Task SignOut_RevokesOnlyThatDevice_AndDeletesNoRecords()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);

        var (access1, refresh1, account1, device1) = await CreateSessionAsync(app, signer, "apple", "signout-sub", "signout@example.com");
        var (access2, refresh2, account2, device2) = await CreateSessionAsync(app, signer, "apple", "signout-sub", "signout@example.com");

        Assert.Equal(account1, account2);
        Assert.NotEqual(device1, device2);

        using var signOutRequest = new HttpRequestMessage(HttpMethod.Delete, "/v1/auth/session");
        signOutRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", access1);
        var signOut = await app.Client.SendAsync(signOutRequest);
        Assert.Equal(HttpStatusCode.NoContent, signOut.StatusCode);

        // Device 1's refresh chain is dead...
        var device1Dead = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.Unauthorized, device1Dead.StatusCode);

        // ...and device 2's tokens keep working.
        var device2Refresh = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh2 });
        Assert.Equal(HttpStatusCode.OK, device2Refresh.StatusCode);

        // No records deleted: the account, both devices, and both refresh chains remain.
        Assert.Equal(1, await app.CountAsync("accounts"));
        Assert.Equal(2, await app.CountAsync("devices"));
        Assert.True(await app.ScalarAsync<bool>("SELECT revoked_at IS NOT NULL FROM refresh_tokens WHERE device_id = @p", new { p = device1 }));
    }

    [SkippableFact]
    public async Task SignOut_WithoutBearerToken_Returns401()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);

        var response = await app.Client.DeleteAsync("/v1/auth/session");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [SkippableFact]
    public async Task AppleAndGoogleSubjects_AreDistinctAccounts()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);

        var appleIdToken = signer.Mint("apple", "shared-sub", "apple@example.com");
        var googleIdToken = signer.Mint("google", "shared-sub", "google@example.com");

        var apple = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken = appleIdToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        var google = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "google",
            idToken = googleIdToken,
            device = new { name = "Pixel", platform = "android" },
        });

        Assert.Equal(HttpStatusCode.OK, apple.StatusCode);
        Assert.Equal(HttpStatusCode.OK, google.StatusCode);

        var appleBody = await apple.Content.ReadFromJsonAsync<SessionResponse>();
        var googleBody = await google.Content.ReadFromJsonAsync<SessionResponse>();
        Assert.NotEqual(appleBody!.AccountId, googleBody!.AccountId);

        Assert.Equal(2, await app.CountAsync("accounts"));
        Assert.Equal(1, await app.CountAsync("accounts", "apple_sub = 'shared-sub'"));
        Assert.Equal(1, await app.CountAsync("accounts", "google_sub = 'shared-sub'"));
    }

    [SkippableFact]
    public async Task NoTokenIdTokenOrEmail_ReachesAnyLogLine()
    {
        var signer = new TestIdTokenSigner();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, writer);

        var idToken = signer.Mint("apple", "log-sub", "log-email@example.com");
        var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionResponse>();

        var refresh = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = body!.RefreshToken });
        Assert.Equal(HttpStatusCode.OK, refresh.StatusCode);

        var all = string.Join('\n', writer.Lines);

        // The pipeline is actually capturing lines (auth.session/auth.refresh).
        Assert.Contains(lines, l => l.Contains("auth.session", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains("auth.refresh", StringComparison.Ordinal));

        // Hard rule 12: no token, idToken, or email appears anywhere.
        Assert.DoesNotContain(idToken, all, StringComparison.Ordinal);
        Assert.DoesNotContain(body.AccessToken, all, StringComparison.Ordinal);
        Assert.DoesNotContain(body.RefreshToken, all, StringComparison.Ordinal);
        Assert.DoesNotContain("log-email@example.com", all, StringComparison.Ordinal);
    }

    private async Task<TestApp> StartAsync(TestIdTokenSigner signer, InMemoryLogWriter? writer = null)
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        var connectionString = db.ConnectionString;

        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b
                .UseEnvironment("Testing")
                .UseSetting("ConnectionStrings:Postgres", connectionString)
                .ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                    if (writer is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton<ILogWriter>(writer));
                    }
                }));

        var client = factory.CreateClient();
        return new TestApp(factory, client, db, signer);
    }

    private static async Task<(string AccessToken, string RefreshToken, Guid AccountId, Guid DeviceId)> CreateSessionAsync(
        TestApp app,
        TestIdTokenSigner signer,
        string provider,
        string subject,
        string email)
    {
        var idToken = signer.Mint(provider, subject, email);
        var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider,
            idToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionResponse>();
        return (body!.AccessToken, body.RefreshToken, body.AccountId, body.DeviceId);
    }

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;
        private readonly HttpClient _client;
        private readonly NpgsqlConnection _db;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db, TestIdTokenSigner signer)
        {
            _factory = factory;
            _client = client;
            _db = db;
            Signer = signer;
        }

        public HttpClient Client => _client;

        public TestIdTokenSigner Signer { get; }

        public Task<int> CountAsync(string table, string? where = null, object? param = null)
            => _db.QuerySingleAsync<int>(
                $"SELECT count(*) FROM {table}" + (where is null ? "" : " WHERE " + where),
                param ?? new { });

        public Task<T> ScalarAsync<T>(string sql, object? param = null)
            => _db.QuerySingleAsync<T>(sql, param ?? new { });

        public async ValueTask DisposeAsync()
        {
            _client.Dispose();
            await _db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
