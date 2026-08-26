using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Tankbook.Api.Auth;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;
using Tankbook.Api.Notifications;
using Tankbook.Api.Tests.Auth;

namespace Tankbook.Api.Tests.Notifications;

/// <summary>
/// L2 tests for the silent sync nudge (docs/NOTIFICATIONS.md) against real
/// Postgres via Testcontainers. The idToken verifier is the test signer and
/// IApnsClient is a recording double - the bearer middleware, the SCN allocator,
/// the throttle claim, the invalidation write and the HTTP surface are all real;
/// only Apple's network is faked (docs/TESTING.md "mock the boundary").
/// </summary>
public class SyncNudgeTests : IClassFixture<PostgresFixture>
{
    private const string PayloadTimestamp = "2026-08-22T12:10:00.000Z";

    private readonly PostgresFixture _fixture;

    public SyncNudgeTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- 1. The pusher is not nudged; its siblings are ---------------------

    [SkippableFact]
    public async Task Push_NudgesSiblings_NotThePusher()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, deviceA) = await CreateSessionAsync(app, signer, "nudge-a", "a@example.com", "iPhone");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "nudge-a", "a@example.com", "iPad");

        await SetTokenAsync(app, deviceA, "apns-token-A");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        var sent = Assert.Single(apns.Sends);
        Assert.Equal("apns-token-B", sent.Token);
        Assert.NotEqual("apns-token-A", sent.Token);
    }

    // ---- 2. The throttle collapses a burst ---------------------------------

    [SkippableFact]
    public async Task Push_TenPushesInsideWindow_NudgeSiblingOnce()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "burst-a", "a@example.com");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "burst-a", "a@example.com", "iPad");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        for (var i = 0; i < 10; i++)
        {
            var response = await PushVehicleAsync(app, tokenA, Guid.NewGuid());
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }

        var sent = Assert.Single(apns.Sends);
        Assert.Equal("apns-token-B", sent.Token);
    }

    // ---- 3. The throttle reopens past the window ---------------------------

    [SkippableFact]
    public async Task Push_PastThrottleWindow_NudgesAgain()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 8, 22, 12, 0, 0, TimeSpan.Zero));
        await using var app = await StartAsync(signer, apns, clock);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "reopen-a", "a@example.com");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "reopen-a", "a@example.com", "iPad");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        await PushVehicleAsync(app, tokenA, Guid.NewGuid());
        Assert.Single(apns.Sends);

        // Advance past the 15-minute window: the next push is eligible again.
        clock.Advance(TimeSpan.FromMinutes(16));
        await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        Assert.Equal(2, apns.Sends.Count);
    }

    // ---- 4. A dead token clears the row ------------------------------------

    [SkippableFact]
    public async Task Push_InvalidToken_ClearsRow_AndNeverNudgesAgain()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "dead-a", "a@example.com");
        var (tokenB, _, deviceB) = await CreateSessionAsync(app, signer, "dead-a", "a@example.com", "iPad");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        apns.OnSend = (_, _) => new ApnsSendResult(ApnsOutcome.InvalidToken, "BadDeviceToken");

        await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        // The dead token is cleared; the device falls back to polling.
        Assert.Null(await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceB }));

        // A second push finds no token to nudge, so the client is not called again.
        await PushVehicleAsync(app, tokenA, Guid.NewGuid());
        Assert.Single(apns.Sends);

        // The sibling's pull still works - a dead token never strands the device.
        Assert.Equal(HttpStatusCode.OK, (await PullAsync(app, tokenB)).StatusCode);
    }

    // ---- 5. A transient failure does NOT clear the token -------------------

    [SkippableFact]
    public async Task Push_TransientFailure_KeepsTheToken()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "blip-a", "a@example.com");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "blip-a", "a@example.com", "iPad");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        apns.OnSend = (_, _) => new ApnsSendResult(ApnsOutcome.TransientFailure, "ServiceUnavailable");

        await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        // The token survives a bad minute: downgrading a healthy device to
        // polling forever would be the bug this test exists to catch.
        Assert.Equal("apns-token-B", await app.ScalarAsync<string?>("SELECT push_token FROM devices WHERE id = @p", new { p = deviceB }));
    }

    // ---- 6. No token: skipped silently, push unaffected --------------------

    [SkippableFact]
    public async Task Push_NoToken_NoNudge_NoError()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "notok-a", "a@example.com");
        _ = await CreateSessionAsync(app, signer, "notok-a", "a@example.com", "iPad"); // no token

        var response = await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty(apns.Sends);
    }

    // ---- 7. APNs completely down: the push still succeeds ------------------

    [SkippableFact]
    public async Task Push_ApnsDown_PushStillSucceeds()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient { OnSend = (_, _) => throw new HttpRequestException("provider down") };
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "down-a", "a@example.com");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "down-a", "a@example.com", "iPad");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        var response = await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        // The nudge is out of band: a dead provider must never change the push result.
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("accepted", doc.RootElement.GetProperty("results")[0].GetProperty("status").GetString());
        Assert.Single(apns.Sends);
    }

    // ---- 8. The payload is silent ------------------------------------------

    [SkippableFact]
    public async Task Push_NudgePayload_IsSilent()
    {
        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        await using var app = await StartAsync(signer, apns);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "payload-a", "a@example.com");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "payload-a", "a@example.com", "iPad");
        await SetTokenAsync(app, deviceB, "apns-token-B");

        await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        var payload = Assert.Single(apns.Sends).PayloadJson;
        using var doc = JsonDocument.Parse(payload);
        var aps = doc.RootElement.GetProperty("aps");
        Assert.Equal(1, aps.GetProperty("content-available").GetInt32());

        // The v1 hard rule expressed as a test: no alert, no sound, no badge - anywhere.
        Assert.DoesNotContain("alert", payload, StringComparison.Ordinal);
        Assert.DoesNotContain("sound", payload, StringComparison.Ordinal);
        Assert.DoesNotContain("badge", payload, StringComparison.Ordinal);
    }

    // ---- 9. No push token reaches a log line -------------------------------

    [SkippableFact]
    public async Task Push_NoPushTokenReachesALog()
    {
        const string secretToken = "apns-log-secret-token-7f3a";

        var signer = new TestIdTokenSigner();
        var apns = new RecordingApnsClient();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, apns, writer: writer);
        var (tokenA, _, _) = await CreateSessionAsync(app, signer, "log-a", "log@example.com");
        var (_, _, deviceB) = await CreateSessionAsync(app, signer, "log-a", "log@example.com", "iPad");
        await SetTokenAsync(app, deviceB, secretToken);

        await PushVehicleAsync(app, tokenA, Guid.NewGuid());

        var all = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The capture is non-empty: the nudge event line was emitted.
        Assert.Contains(lines, l => l.Contains("sync.nudge", StringComparison.Ordinal));

        // Hard rule 12: a push token is a credential and never reaches any log line.
        Assert.DoesNotContain(secretToken, all, StringComparison.Ordinal);
    }

    // ---- 10. The config hint rides the same silent body --------------------

    [Fact]
    public void ApnsPayload_ConfigHint_IsSilentAndFlagged()
    {
        using var doc = JsonDocument.Parse(ApnsPayload.Silent(config: true));
        Assert.Equal(1, doc.RootElement.GetProperty("aps").GetProperty("content-available").GetInt32());
        Assert.True(doc.RootElement.GetProperty("config").GetBoolean());

        using var plain = JsonDocument.Parse(ApnsPayload.Silent(config: false));
        Assert.False(plain.RootElement.TryGetProperty("config", out _));
    }

    // ---- helpers -----------------------------------------------------------

    private async Task<TestApp> StartAsync(
        TestIdTokenSigner signer,
        RecordingApnsClient apns,
        TimeProvider? time = null,
        InMemoryLogWriter? writer = null)
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
                    services.Replace(ServiceDescriptor.Singleton<IApnsClient>(apns));
                    if (time is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton(time));
                    }

                    if (writer is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton<ILogWriter>(writer));
                    }
                }));

        var client = factory.CreateClient();
        return new TestApp(factory, client, db, signer, apns);
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

    private static async Task SetTokenAsync(TestApp app, Guid deviceId, string token)
        => await app.Db.ExecuteAsync(
            "UPDATE devices SET push_token = @token WHERE id = @id",
            new { token, id = deviceId });

    private static async Task<HttpResponseMessage> PushVehicleAsync(TestApp app, string token, Guid id)
    {
        var change = new JsonObject
        {
            ["id"] = id.ToString(),
            ["entityType"] = "vehicle",
            ["schemaVersion"] = 1,
            ["baseScn"] = 0,
            ["payload"] = JsonNode.Parse(VehiclePayload(id))!,
            ["clientUpdatedAt"] = PayloadTimestamp,
            ["deleted"] = false,
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/sync/push");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { changes = new JsonArray(change) });
        return await app.Client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> PullAsync(TestApp app, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/sync/pull?since=0&limit=500");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await app.Client.SendAsync(request);
    }

    private static string VehiclePayload(Guid id) => $$"""
        {
          "id": "{{id}}",
          "createdAt": "2026-01-10T09:30:00.000Z",
          "updatedAt": "2026-08-22T12:10:00.000Z",
          "name": "Volvo V60",
          "powertrain": "hybrid",
          "fuelKinds": ["petrol95", "electricity"],
          "homeCurrency": "EUR",
          "units": { "distance": "km", "volume": "l", "consumption": "lPer100", "energy": "kWhPer100" },
          "archived": false,
          "paceLimitKmPerDay": 1500
        }
        """;

    /// <summary>A settable <see cref="TimeProvider"/> so the throttle window can be driven deterministically without sleeping.</summary>
    private sealed class MutableTimeProvider : TimeProvider
    {
        private DateTimeOffset _now;

        public MutableTimeProvider(DateTimeOffset now) => _now = now;

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan span) => _now += span;
    }

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;
        private readonly HttpClient _client;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db, TestIdTokenSigner signer, RecordingApnsClient apns)
        {
            _factory = factory;
            _client = client;
            Db = db;
            Signer = signer;
            Apns = apns;
        }

        public HttpClient Client => _client;

        public NpgsqlConnection Db { get; }

        public TestIdTokenSigner Signer { get; }

        public RecordingApnsClient Apns { get; }

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
