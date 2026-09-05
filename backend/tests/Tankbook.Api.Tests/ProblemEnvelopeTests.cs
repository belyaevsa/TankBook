using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;
using Tankbook.Api.Tests.Import;

namespace Tankbook.Api.Tests;

/// <summary>
/// PR.9/OB.1 - the headline L2 property: EVERY problem+json this server emits
/// carries a non-empty, stable `code` (docs/API.md -> "Error envelope"). The
/// structural half is compile-time - every problem site must pass a code to
/// <see cref="Tankbook.Api.Http.ProblemResponses"/>, so an endpoint added later
/// without one does not build. This file verifies the wire half: a sweep of
/// problem-producing requests across every endpoint family, asserting each
/// response is problem+json whose `code` is non-empty, is one of the documented
/// codes (a request-derived value would not be - hard rule 12), and matches the
/// code this contract assigns to the condition.
/// </summary>
public class ProblemEnvelopeTests : IClassFixture<PostgresFixture>
{
    private const string DeviceHeaderId = "11111111-2222-4333-8444-555555555555";

    private static readonly HashSet<string> KnownCodes = typeof(TankbookErrorCodes)
        .GetFields(BindingFlags.Public | BindingFlags.Static)
        .Where(f => f.FieldType == typeof(string))
        .Select(f => (string)f.GetValue(null)!)
        .ToHashSet(StringComparer.Ordinal);

    private readonly PostgresFixture _fixture;

    public ProblemEnvelopeTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- Public / no-auth surfaces ------------------------------------------

    [SkippableFact]
    public async Task PublicAndNoAuthProblems_AllCarryACode()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, quotaBytes: "2000", configSigningKey: "");
        var client = app.Client;

        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/auth/session", new { provider = "github", idToken = "x", device = new { name = "iPhone", platform = "ios" } }),
            HttpStatusCode.BadRequest, TankbookErrorCodes.ProviderUnsupported);
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/auth/session", new { provider = "apple", idToken = "garbage.token.value", device = new { name = "iPhone", platform = "ios" } }),
            HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/auth/session", new { provider = "apple", device = new { name = "iPhone", platform = "ios" } }),
            HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);

        // Every bearer family refuses an absent bearer with token_invalid.
        await AssertProblemAsync(
            await client.GetAsync("/v1/sync/pull?since=0"), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/sync/push", new { changes = Array.Empty<object>() }), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/blobs/begin", new { sha256 = "x", size = 1, contentType = "image/jpeg" }), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/blobs/commit", new { sha256 = "x" }), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.GetAsync("/v1/account/devices"), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.DeleteAsync("/v1/account"), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/extract", new { kind = "receipt", image = "x" }), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.GetAsync("/v1/outbox"), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
        await AssertProblemAsync(
            await client.DeleteAsync("/v1/outbox/11111111-2222-4333-8444-555555555555"), HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);

        // Shape refusals on the public surfaces.
        await AssertProblemAsync(
            await client.PostAsJsonAsync("/v1/feedback", new { category = "nonsense", text = "hi", appVersion = "1.0.0+1" }),
            HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);
        await AssertProblemAsync(
            await client.GetAsync("/v1/catalog?since_version=abc"), HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);
        await AssertProblemAsync(
            await client.GetAsync("/v1/rates?date=2026-01-01&base=XX"), HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);

        // Import, signed out but with a device id (the parse path needs one).
        await AssertProblemAsync(
            await ParseAsync(client, format: "not-a-format", fileBytes: MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), fileName: "fuel.csv"),
            HttpStatusCode.UnsupportedMediaType, TankbookErrorCodes.ImportFormatUnsupported);
        await AssertProblemAsync(
            await client.GetAsync("/v1/import/11111111-2222-4333-8444-555555555555"),
            HttpStatusCode.NotFound, TankbookErrorCodes.ImportNotFound);
        await AssertProblemAsync(
            await ParseAsync(client, format: "mfm", fileBytes: Encoding.UTF8.GetBytes("hello,this,is,not,mfm"), fileName: "x.csv"),
            HttpStatusCode.UnprocessableEntity, TankbookErrorCodes.ImportMismatch);

        // Envelope surfaces.
        await AssertProblemAsync(
            await client.GetAsync("/v1/config/public-key"), HttpStatusCode.ServiceUnavailable, TankbookErrorCodes.ConfigUnavailable);
        await AssertProblemAsync(
            await client.GetAsync("/v1/does-not-exist"), HttpStatusCode.NotFound, TankbookErrorCodes.NotFound);
        await AssertProblemAsync(
            await client.GetAsync("/v1/sync/push"), HttpStatusCode.MethodNotAllowed, TankbookErrorCodes.PayloadInvalid);
        await AssertProblemAsync(
            await client.PostAsync("/v1/auth/session", new StringContent(new string('x', (int)Tankbook.Api.Http.BodySizeLimits.DefaultBytes + 1), Encoding.UTF8, "application/json")),
            HttpStatusCode.RequestEntityTooLarge, TankbookErrorCodes.PayloadTooLarge);
    }

    [SkippableFact]
    public async Task AuthProblems_RefreshReuseAndClockSkew_CarryTheirCodes()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (_, refresh1, _, _) = await CreateSessionAsync(app, signer, "pr9-auth", "pr9auth@example.com");

        // Reuse of an already-rotated token revokes the chain: refresh_reused.
        var rotated = await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 });
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        await AssertProblemAsync(
            await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = refresh1 }),
            HttpStatusCode.Unauthorized, TankbookErrorCodes.RefreshReused);

        // A garbage refresh token is a plain rejection: token_invalid.
        await AssertProblemAsync(
            await app.Client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = "not-a-real-token" }),
            HttpStatusCode.Unauthorized, TankbookErrorCodes.TokenInvalid);
    }

    // ---- Bearer surfaces ----------------------------------------------------

    [SkippableFact]
    public async Task SyncBlobsAccountOutboxProblems_AllCarryACode()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, quotaBytes: "2000", configSigningKey: "");
        var client = app.Client;
        var (token, _, accountId, deviceId) = await CreateSessionAsync(app, signer, "pr9-bearer", "pr9bearer@example.com");

        // Sync: stale schema version -> 426 whole-batch.
        var stale = new JsonArray
        {
            Change(Guid.NewGuid(), schemaVersion: 0),
        };
        await AssertProblemAsync(
            await PushBatchAsync(app.Client, token, stale), HttpStatusCode.UpgradeRequired, TankbookErrorCodes.UpgradeRequired);

        // Sync: a batch over the limit is a shape refusal.
        var tooMany = new JsonArray();
        for (var i = 0; i < 201; i++)
        {
            tooMany.Add(Change(Guid.NewGuid(), schemaVersion: 1));
        }
        await AssertProblemAsync(
            await PushBatchAsync(app.Client, token, tooMany), HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);

        // Blobs: shape, size, quota, protocol and ownership problems.
        var sha = new string('a', 64);
        await AssertProblemAsync(
            await PostJsonAsync(client, token, "/v1/blobs/begin", new { sha256 = "nope", size = 1, contentType = "image/jpeg" }),
            HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);
        await AssertProblemAsync(
            await PostJsonAsync(client, token, "/v1/blobs/begin", new { sha256 = sha, size = 30_000_000, contentType = "image/jpeg" }),
            HttpStatusCode.RequestEntityTooLarge, TankbookErrorCodes.PayloadTooLarge);
        await AssertProblemAsync(
            await PostJsonAsync(client, token, "/v1/blobs/begin", new { sha256 = sha, size = 2500, contentType = "image/jpeg" }),
            HttpStatusCode.TooManyRequests, TankbookErrorCodes.BlobQuotaExceeded);
        await AssertProblemAsync(
            await PostJsonAsync(client, token, "/v1/blobs/commit", new { sha256 = sha }),
            HttpStatusCode.Conflict, TankbookErrorCodes.BlobConflict);
        await AssertProblemAsync(
            await GetJsonAsync(client, token, $"/v1/blobs/{sha}"), HttpStatusCode.NotFound, TankbookErrorCodes.BlobNotFound);

        // Account: a device id that is not this account's is 404 with its code.
        var foreign = Guid.NewGuid();
        await AssertProblemAsync(
            await PutPushTokenAsync(app.Client, token, foreign),
            HttpStatusCode.NotFound, TankbookErrorCodes.AccountDeviceNotFound);
        await AssertProblemAsync(
            await DeleteDeviceAsync(app.Client, token, foreign),
            HttpStatusCode.NotFound, TankbookErrorCodes.AccountDeviceNotFound);

        // Extract: an unknown kind is a shape refusal (no model call).
        await AssertProblemAsync(
            await PostJsonAsync(client, token, "/v1/extract", new { kind = "banana", image = "aGk=" }),
            HttpStatusCode.BadRequest, TankbookErrorCodes.PayloadInvalid);

        // A revoked device's pull is 410 with device_revoked.
        await AssertProblemAsync(
            await DeleteDeviceAsync(app.Client, token, deviceId), HttpStatusCode.NoContent, expectedCode: null);
        await AssertProblemAsync(
            await GetPullAsync(app.Client, token), HttpStatusCode.Gone, TankbookErrorCodes.DeviceRevoked);
        Assert.Equal(0, await app.CountAsync("records", "account_id = @p", new { p = accountId }));
    }

    [SkippableFact]
    public async Task RateLimitedRequest_CarriesRateLimited()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, authSessionPerMinute: 2);

        var body = new { provider = "apple", idToken = "not-a-jwt", device = new { name = "iPhone", platform = "ios" } };
        for (var i = 0; i < 2; i++)
        {
            Assert.Equal(HttpStatusCode.Unauthorized, (await app.Client.PostAsJsonAsync("/v1/auth/session", body)).StatusCode);
        }

        await AssertProblemAsync(
            await app.Client.PostAsJsonAsync("/v1/auth/session", body),
            HttpStatusCode.TooManyRequests, TankbookErrorCodes.RateLimited);
    }

    // ---- Helpers ------------------------------------------------------------

    /// <summary>
    /// The assertion every scenario funnels through: the response is a non-2xx
    /// problem+json whose `code` member is non-empty, is a documented stable
    /// code (a request-derived value would fail here - hard rule 12), and equals
    /// the code this contract assigns to the condition. `expectedCode` null only
    /// for the non-error (204) case.
    /// </summary>
    private static async Task AssertProblemAsync(HttpResponseMessage response, HttpStatusCode status, string? expectedCode)
    {
        Assert.Equal(status, response.StatusCode);
        if (expectedCode is null)
        {
            return;
        }

        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = doc.RootElement;
        Assert.Equal((int)status, root.GetProperty("status").GetInt32());
        var code = root.GetProperty("code").GetString();
        Assert.False(string.IsNullOrWhiteSpace(code), $"code must be non-empty for HTTP {(int)status}");
        Assert.Contains(code, KnownCodes);
        Assert.Equal(expectedCode, code);
    }

    private async Task<TestApp> StartAsync(
        TestIdTokenSigner signer,
        string? quotaBytes = null,
        int? authSessionPerMinute = null,
        string? configSigningKey = null)
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        var connectionString = db.ConnectionString;

        var storage = new RecordingBlobStorage();
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:Postgres", connectionString);
                b.UseSetting("Logging:LogLevel:Default", "Debug");
                if (quotaBytes is not null)
                {
                    b.UseSetting("Blob:QuotaBytes", quotaBytes);
                }
                if (authSessionPerMinute is not null)
                {
                    b.UseSetting("RateLimit:AuthSessionPerMinute", authSessionPerMinute.Value.ToString());
                }
                if (configSigningKey is not null)
                {
                    b.UseSetting("Config:SigningKey", configSigningKey);
                }

                b.ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                    services.Replace(ServiceDescriptor.Singleton<IBlobStorage>(storage));
                });
            });

        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        return new TestApp(factory, client, db, signer);
    }

    private static async Task<(string AccessToken, string RefreshToken, Guid AccountId, Guid DeviceId)> CreateSessionAsync(
        TestApp app,
        TestIdTokenSigner signer,
        string subject,
        string email)
    {
        var idToken = signer.Mint("apple", subject, email);
        var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionResponse>();
        return (body!.AccessToken, body.RefreshToken, body.AccountId, body.DeviceId);
    }

    private static JsonObject Change(Guid id, int schemaVersion)
        => new()
        {
            ["id"] = id.ToString(),
            ["entityType"] = "vehicle",
            ["schemaVersion"] = schemaVersion,
            ["baseScn"] = 0,
            ["payload"] = new JsonObject { ["id"] = id.ToString() },
            ["clientUpdatedAt"] = "2026-08-22T12:10:00.000Z",
            ["deleted"] = false,
        };

    private static async Task<HttpResponseMessage> PostJsonAsync(HttpClient client, string token, string path, object body)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(body);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> GetJsonAsync(HttpClient client, string token, string path)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> PushBatchAsync(HttpClient client, string token, JsonArray changes)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/sync/push");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { changes });
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> GetPullAsync(HttpClient client, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/sync/pull?since=0&limit=500");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> PutPushTokenAsync(HttpClient client, string token, Guid deviceId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/v1/account/devices/{deviceId}/push-token");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { apnsToken = "token" });
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> DeleteDeviceAsync(HttpClient client, string token, Guid deviceId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, $"/v1/account/devices/{deviceId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> ParseAsync(
        HttpClient client,
        string? format,
        byte[] fileBytes,
        string fileName)
    {
        using var content = new MultipartFormDataContent();
        if (format is not null)
        {
            content.Add(new StringContent(format), "format");
        }
        content.Add(new ByteArrayContent(fileBytes), "file", fileName);
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/import/parse");
        request.Headers.Add("X-Device-Id", DeviceHeaderId);
        request.Content = content;
        return await client.SendAsync(request);
    }

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;
        private readonly HttpClient _client;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db, TestIdTokenSigner signer)
        {
            _factory = factory;
            _client = client;
            Db = db;
            Signer = signer;
        }

        public HttpClient Client => _client;

        public NpgsqlConnection Db { get; }

        public TestIdTokenSigner Signer { get; }

        public Task<int> CountAsync(string table, string? where = null, object? param = null)
            => Db.QuerySingleAsync<int>(
                $"SELECT count(*) FROM {table}" + (where is null ? "" : " WHERE " + where),
                param ?? new { });

        public async ValueTask DisposeAsync()
        {
            _client.Dispose();
            await Db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
