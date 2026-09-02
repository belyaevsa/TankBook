using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Tankbook.Api.Auth;
using Tankbook.Api.Data;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;
using Tankbook.Api.Tests.Auth;

namespace Tankbook.Api.Tests.RateLimiting;

/// <summary>
/// L2 tests for PR.17 (docs/API.md "Rate limits" and "Request body caps",
/// docs/PRACTICES.md S9): the rate limiter rejects an over-limit device with a
/// 429 carrying Retry-After, an oversize body is a 413 problem+json carrying its
/// traceId, and a maximal legal push batch is not rejected by the body cap.
/// </summary>
public class RateLimitAndBodyCapTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public RateLimitAndBodyCapTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task AuthSession_OverRateLimit_Returns429WithRetryAfter()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, authSessionPerMinute: 2);

        var body = new { provider = "apple", idToken = "not-a-jwt", device = new { name = "iPhone", platform = "ios" } };

        // Two requests inside the window are permitted (each answers 401 for the
        // bogus idToken, but the rate limiter counts them). The third is refused.
        for (var i = 0; i < 2; i++)
        {
            using var permitted = await app.Client.PostAsJsonAsync("/v1/auth/session", body);
            Assert.Equal(HttpStatusCode.Unauthorized, permitted.StatusCode);
        }

        using var rejected = await app.Client.PostAsJsonAsync("/v1/auth/session", body);
        Assert.Equal(HttpStatusCode.TooManyRequests, rejected.StatusCode);
        Assert.False(string.IsNullOrWhiteSpace(rejected.Headers.RetryAfter?.ToString()));
    }

    [SkippableFact]
    public async Task AuthSession_BodyOneByteOverCap_Returns413ProblemJsonWithTraceId()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);

        var oversized = new string('x', (int)BodySizeLimits.DefaultBytes + 1);
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/auth/session")
        {
            Content = new StringContent(oversized, Encoding.UTF8, "application/json"),
        };
        using var response = await app.Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);

        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(413, document.RootElement.GetProperty("status").GetInt32());
        Assert.True(document.RootElement.TryGetProperty("traceId", out var traceId));
        Assert.False(string.IsNullOrWhiteSpace(traceId.GetString()));
    }

    [SkippableFact]
    public async Task SyncPush_MaximalBatch_Returns200()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, _, _) = await CreateSessionAsync(app, signer);

        // A maximal legal batch: 200 changes, each payload ~200 KB (under the
        // 256 KB payload cap), ~40 MB in total - comfortably above the old
        // Kestrel 30 MB default, so this asserts the raised push cap accepts a
        // legitimate client that the previous limit would have reset.
        var pad = new string('x', 200 * 1024);
        var payload = JsonNode.Parse($$"""{"pad":"{{pad}}"}""")!;
        var changes = new JsonArray();
        for (var i = 0; i < 200; i++)
        {
            changes.Add(new JsonObject
            {
                ["id"] = Guid.NewGuid().ToString(),
                ["entityType"] = "bulktest",
                ["schemaVersion"] = 1,
                ["baseScn"] = 0,
                ["payload"] = payload.DeepClone(),
                ["clientUpdatedAt"] = "2026-08-22T12:10:00.000Z",
                ["deleted"] = false,
            });
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/sync/push");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { changes });
        using var response = await app.Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private async Task<TestApp> StartAsync(TestIdTokenSigner signer, int? authSessionPerMinute = null)
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
                // A SUCCESSFUL request line is Debug since 2026-09-02 (only
                // failures are Information). The log-assertion tests read that
                // line for its correlation fields, so the test host captures at
                // Debug - the guarantee is unchanged, its level is not.
                b.UseSetting("Logging:LogLevel:Default", "Debug");
                if (authSessionPerMinute is not null)
                {
                    b.UseSetting("RateLimit:AuthSessionPerMinute", authSessionPerMinute.Value.ToString());
                }

                b.ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                });
            });

        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        return new TestApp(factory, client, db);
    }

    private static async Task<(string AccessToken, Guid AccountId, Guid DeviceId)> CreateSessionAsync(
        TestApp app,
        TestIdTokenSigner signer)
    {
        var idToken = signer.Mint("apple", "rate-sub", "rate@example.com");
        using var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionResponse>();
        return (body!.AccessToken, body.AccountId, body.DeviceId);
    }

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;
        private readonly HttpClient _client;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db)
        {
            _factory = factory;
            _client = client;
            Db = db;
        }

        public HttpClient Client => _client;

        public NpgsqlConnection Db { get; }

        public async ValueTask DisposeAsync()
        {
            _client.Dispose();
            await Db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
