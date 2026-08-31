using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
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

namespace Tankbook.Api.Tests.Feedback;

/// <summary>
/// L2 tests for POST /feedback (docs/API.md "Feedback") against real Postgres
/// via Testcontainers. The endpoint is public with the bearer optional: feedback
/// must work for a user with no account. 202 means accepted, and the row is
/// written before the response - so asserting the status alone is not enough,
/// the stored row is asserted too. The body cap and the rate limiter are PR.17's
/// real machinery, exercised here rather than re-implemented.
/// </summary>
public class FeedbackEndpointTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public FeedbackEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- the happy path: 202 AND the row exists -----------------------------

    [SkippableFact]
    public async Task Submit_ValidBody_Returns202_AndPersistsTheRow()
    {
        await using var app = await StartAsync();

        using var response = await PostAsync(app.Client, new
        {
            category = "feature",
            text = "the log book overflows on the trends screen",
            appVersion = "1.2.3",
            deviceModel = "iPhone 17",
            replyTo = "driver@example.com",
        });

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);

        // 202 with nothing persisted is the vacuous version of this task: the
        // row must exist, with the category and text verbatim.
        Assert.Equal(1, await app.CountAsync("feedback"));
        var (category, text) = await app.QueryRowAsync("SELECT category, text FROM feedback");
        Assert.Equal("feature", category);
        Assert.Equal("the log book overflows on the trends screen", text);
        Assert.True(await app.ScalarAsync<bool>("SELECT account_id IS NULL FROM feedback"));

        // The metadata envelope (appVersion, deviceModel, replyTo) lives in the
        // meta jsonb. replyTo is user-supplied contact data - stored, never logged.
        var meta = await app.ScalarAsync<string>("SELECT meta::text FROM feedback");
        using var document = JsonDocument.Parse(meta);
        Assert.Equal("1.2.3", document.RootElement.GetProperty("appVersion").GetString());
        Assert.Equal("iPhone 17", document.RootElement.GetProperty("deviceModel").GetString());
        Assert.Equal("driver@example.com", document.RootElement.GetProperty("replyTo").GetString());
    }

    // ---- public: bearer optional --------------------------------------------

    [SkippableFact]
    public async Task Submit_WithBearer_AttachesAccountId_AndAbsenceDoesNot401()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (accessToken, accountId) = await CreateSessionAsync(app, signer);

        // With a bearer the case is attributed to the account.
        using var authed = await PostAsync(app.Client, new
        {
            category = "problem",
            text = "sync stalls on large cars",
            appVersion = "1.2.3",
        }, accessToken);
        Assert.Equal(HttpStatusCode.Accepted, authed.StatusCode);
        Assert.Equal(1, await app.CountAsync("feedback", "account_id = @p", new { p = accountId }));

        // Without a bearer the same endpoint still accepts - absent account is
        // not an error, the case is stored with a NULL account_id.
        using var signedOut = await PostAsync(app.Client, new
        {
            category = "other",
            text = "no account, still complaining",
            appVersion = "1.2.3",
        });
        Assert.Equal(HttpStatusCode.Accepted, signedOut.StatusCode);
        Assert.Equal(2, await app.CountAsync("feedback"));
        Assert.Equal(1, await app.CountAsync("feedback", "account_id = @p", new { p = accountId }));
        Assert.Equal(1, await app.CountAsync("feedback", "account_id IS NULL"));
    }

    // ---- structural validation (rule 9: shape, never meaning) ---------------

    [SkippableFact]
    public async Task Submit_InvalidCategory_Returns400()
    {
        await using var app = await StartAsync();

        using var response = await PostAsync(app.Client, new
        {
            category = "urgent",
            text = "this category does not exist in the contract",
            appVersion = "1.2.3",
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(0, await app.CountAsync("feedback"));
    }

    // ---- the body cap is PR.17's real machinery ------------------------------

    [SkippableFact]
    public async Task Submit_OversizeBody_IsRefusedWith413ProblemJsonAndTraceId()
    {
        await using var app = await StartAsync();

        var oversized = new string('x', (int)BodySizeLimits.FeedbackBytes + 1);
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/feedback")
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
        Assert.Equal(0, await app.CountAsync("feedback"));
    }

    // ---- the rate limiter is PR.17's real machinery --------------------------

    [SkippableFact]
    public async Task Submit_OverRateLimit_Returns429WithRetryAfter()
    {
        await using var app = await StartAsync(feedbackPerMinute: 2);
        var deviceId = Guid.NewGuid().ToString("N");

        // Two requests inside the window are accepted; the third is refused.
        for (var i = 0; i < 2; i++)
        {
            using var permitted = await PostAsync(app.Client, new
            {
                category = "feature",
                text = "rate probe " + i,
                appVersion = "1.2.3",
            }, deviceId: deviceId);
            Assert.Equal(HttpStatusCode.Accepted, permitted.StatusCode);
        }

        using var rejected = await PostAsync(app.Client, new
        {
            category = "feature",
            text = "rate probe over the limit",
            appVersion = "1.2.3",
        }, deviceId: deviceId);
        Assert.Equal(HttpStatusCode.TooManyRequests, rejected.StatusCode);
        Assert.False(string.IsNullOrWhiteSpace(rejected.Headers.RetryAfter?.ToString()));
        Assert.Equal(2, await app.CountAsync("feedback"));
    }

    // ---- hard rule 12: nothing but shape is logged ---------------------------

    [SkippableFact]
    public async Task Submit_LogsCarryShapeOnly_NeverFixtureValues()
    {
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(writer: writer);

        using var response = await PostAsync(app.Client, new
        {
            category = "problem",
            text = "REDACT-FB-LINE-NINETY-TWO the log book overflows again",
            appVersion = "1.2.3",
            deviceModel = "RedactProbe 9f",
            replyTo = "redact-probe-3f@example.com",
        });
        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);

        var all = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The pipeline captured the acceptance event (not an empty sweep).
        var acceptedLines = writer.Lines.Count(l => l.Contains("feedback.accepted", StringComparison.Ordinal));
        Assert.True(acceptedLines >= 1, $"expected feedback.accepted lines, saw {acceptedLines}");

        // Shape survives: the category code, the length count, the presence flags.
        Assert.Contains("\"Category\":\"problem\"", all, StringComparison.Ordinal);
        Assert.Contains("TextLength", all, StringComparison.Ordinal);
        Assert.Contains("HasReplyTo", all, StringComparison.Ordinal);
        Assert.Contains("HasDeviceModel", all, StringComparison.Ordinal);

        // Hard rule 12: never the feedback text, never the replyTo address,
        // never the device-model string.
        Assert.DoesNotContain("REDACT-FB-LINE-NINETY-TWO", all, StringComparison.Ordinal);
        Assert.DoesNotContain("redact-probe-3f@example.com", all, StringComparison.Ordinal);
        Assert.DoesNotContain("RedactProbe 9f", all, StringComparison.Ordinal);
    }

    // ---- plumbing ------------------------------------------------------------

    private async Task<TestApp> StartAsync(
        TestIdTokenSigner? signer = null,
        InMemoryLogWriter? writer = null,
        int? feedbackPerMinute = null)
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
                if (feedbackPerMinute is not null)
                {
                    b.UseSetting("RateLimit:FeedbackPerMinute", feedbackPerMinute.Value.ToString());
                }

                b.ConfigureServices(services =>
                {
                    if (signer is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                    }

                    if (writer is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton<ILogWriter>(writer));
                    }
                });
            });

        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        return new TestApp(factory, client, db);
    }

    private static Task<HttpResponseMessage> PostAsync(HttpClient client, object body, string? bearer = null, string? deviceId = null)
        => PostAsync(client, JsonContent.Create(body), bearer, deviceId);

    private static async Task<HttpResponseMessage> PostAsync(HttpClient client, HttpContent content, string? bearer = null, string? deviceId = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/feedback") { Content = content };
        if (bearer is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        }

        if (deviceId is not null)
        {
            request.Headers.TryAddWithoutValidation("X-Device-Id", deviceId);
        }

        return await client.SendAsync(request);
    }

    private static async Task<(string AccessToken, Guid AccountId)> CreateSessionAsync(TestApp app, TestIdTokenSigner signer)
    {
        var idToken = signer.Mint("apple", "feedback-sub-" + Guid.NewGuid().ToString("N"), "feedback@example.com");
        using var response = await app.Client.PostAsJsonAsync("/v1/auth/session", new
        {
            provider = "apple",
            idToken,
            device = new { name = "iPhone", platform = "ios" },
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return (body.RootElement.GetProperty("accessToken").GetString()!, body.RootElement.GetProperty("accountId").GetGuid());
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

        public Task<int> CountAsync(string table, string? where = null, object? param = null)
            => Db.QuerySingleAsync<int>(
                $"SELECT count(*) FROM {table}" + (where is null ? "" : " WHERE " + where),
                param ?? new { });

        public Task<T> ScalarAsync<T>(string sql, object? param = null)
            => Db.QuerySingleAsync<T>(sql, param ?? new { });

        public Task<(string, string)> QueryRowAsync(string sql, object? param = null)
            => Db.QuerySingleAsync<(string, string)>(sql, param ?? new { });

        public async ValueTask DisposeAsync()
        {
            _client.Dispose();
            await Db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
