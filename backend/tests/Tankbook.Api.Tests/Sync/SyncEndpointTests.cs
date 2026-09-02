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
using Tankbook.Api.Tests.Auth;

namespace Tankbook.Api.Tests.Sync;

/// <summary>
/// L2 tests for the sync endpoints (docs/API.md Sync) against real Postgres via
/// Testcontainers. The idToken verifier is the test signer (docs/TESTING.md
/// "mock the boundary"): the bearer middleware, the SCN allocator, the payload
/// validator, the record stream and the HTTP surface are all real.
/// </summary>
public class SyncEndpointTests : IClassFixture<PostgresFixture>
{
    private const string PayloadTimestamp = "2026-08-22T12:10:00.000Z";

    private readonly PostgresFixture _fixture;

    public SyncEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- 1. Ordering and pagination under concurrent writes -----------------

    [SkippableFact]
    public async Task Pull_UnderConcurrentWrites_NeverSkipsARecord()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, _, _) = await CreateSessionAsync(app, signer, "pag-sub", "pag@example.com");

        const int writers = 30;
        var ids = Enumerable.Range(0, writers).Select(_ => Guid.NewGuid()).ToArray();

        // Fire every writer in parallel, then page through the stream while the
        // writes are still in flight.
        var writerTasks = ids.Select(id => PushOneAsync(app.Client, token, NewVehicleChange(id, baseScn: 0))).ToArray();

        var pulled = new Dictionary<Guid, long>();
        var cursor = 0L;
        var more = true;
        while (more)
        {
            var page = await PullAsync(app.Client, token, cursor, limit: 7);
            Assert.Equal(HttpStatusCode.OK, page.StatusCode);
            foreach (var record in page.Records)
            {
                pulled[record.Id] = record.Scn;
            }

            cursor = page.NextSince;
            more = page.More;
        }

        await Task.WhenAll(writerTasks);

        // Final drain after every writer has committed - the reader's cursor must
        // not have advanced past anything still in flight.
        more = true;
        while (more)
        {
            var page = await PullAsync(app.Client, token, cursor, limit: 7);
            Assert.Equal(HttpStatusCode.OK, page.StatusCode);
            foreach (var record in page.Records)
            {
                pulled[record.Id] = record.Scn;
            }

            cursor = page.NextSince;
            more = page.More;
        }

        // The assertion that catches a cursor that advanced past an in-flight
        // commit: the union of pages is exactly the full set, every id exactly once.
        Assert.Equal(ids.OrderBy(x => x).ToArray(), pulled.Keys.OrderBy(x => x).ToArray());
        Assert.Equal(Enumerable.Range(1, writers).Select(i => (long)i).ToArray(), pulled.Values.OrderBy(x => x).ToArray());
    }

    // ---- 2. Idempotent replay ----------------------------------------------

    [SkippableFact]
    public async Task Push_Replay_IsIdempotent_OneRowPerId()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "replay-sub", "replay@example.com");

        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var c = Guid.NewGuid();
        var batch = new[] { NewVehicleChange(a, 0), NewVehicleChange(b, 0), NewVehicleChange(c, 0) };

        var first = await PushBatchAsync(app.Client, token, batch);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var firstScns = await AcceptedScnsAsync(first);

        // Replay the identical batch: same accepted outcomes, same SCNs, no new rows.
        var second = await PushBatchAsync(app.Client, token, batch);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(firstScns, await AcceptedScnsAsync(second));

        Assert.Equal(3, await app.CountAsync("records", "account_id = @p", new { p = accountId }));
        Assert.Equal(3L, await app.ScalarAsync<long>("SELECT next_scn FROM account_seq WHERE account_id = @p", new { p = accountId }));
    }

    // ---- 3. Per-item conflict ----------------------------------------------

    [SkippableFact]
    public async Task Push_PerItemConflict_ReturnsCurrent_AndOthersSucceed()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "conf-sub", "conf@example.com");

        var original = Guid.NewGuid();
        var first = await PushBatchAsync(app.Client, token, new[] { NewVehicleChange(original, 0) });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(1L, (await AcceptedScnsAsync(first))[0]);

        // A batch mixing a stale update with two fresh records: only the stale
        // item conflicts; the other two must still succeed (partial success is
        // the contract, an all-or-nothing batch is wrong).
        var newOne = Guid.NewGuid();
        var newTwo = Guid.NewGuid();
        var batch = new[]
        {
            NewVehicleChange(original, baseScn: 999), // stale base -> conflict
            NewVehicleChange(newOne, baseScn: 0),
            NewVehicleChange(newTwo, baseScn: 0),
        };

        var response = await PushBatchAsync(app.Client, token, batch);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Equal(3, results.Length);

        Assert.Equal("conflict", results[0].GetProperty("status").GetString());
        var current = results[0].GetProperty("current");
        Assert.Equal(original, Guid.Parse(current.GetProperty("id").GetString()!));
        Assert.Equal(1L, current.GetProperty("scn").GetInt64());
        Assert.Equal("vehicle", current.GetProperty("entityType").GetString());
        Assert.Equal(JsonValueKind.Object, current.GetProperty("payload").ValueKind);

        Assert.Equal("accepted", results[1].GetProperty("status").GetString());
        Assert.Equal("accepted", results[2].GetProperty("status").GetString());
        Assert.Equal(2L, results[1].GetProperty("newScn").GetInt64());
        Assert.Equal(3L, results[2].GetProperty("newScn").GetInt64());

        // The original row is untouched; two new rows landed.
        Assert.Equal(3, await app.CountAsync("records", "account_id = @p", new { p = accountId }));
        Assert.Equal(1L, await app.ScalarAsync<long>("SELECT scn FROM records WHERE account_id = @p AND id = @id", new { p = accountId, id = original }));
    }

    // ---- 4. rejected carries a code and a pointer ---------------------------

    [SkippableFact]
    public async Task Push_Rejected_CarriesCodeAndPointer_OthersUnaffected()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "rej-sub", "rej@example.com");

        var badUuid = Guid.NewGuid();
        var good = Guid.NewGuid();
        var notObject = Guid.NewGuid();

        var batch = new JsonArray
        {
            // A schema violation: bad uuid -> rejected with a JSON pointer.
            Change(badUuid, 0, JsonNode.Parse(VehiclePayload(badUuid).Replace($"\"{badUuid}\"", "\"not-a-uuid\"", StringComparison.Ordinal))!),
            NewVehicleChange(good, 0),
            // A non-object payload -> payload_invalid (no pointer).
            Change(notObject, 0, JsonNode.Parse("[1,2,3]")!),
        };

        var response = await PushBatchAsync(app.Client, token, batch);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Equal(3, results.Length);

        Assert.Equal("rejected", results[0].GetProperty("status").GetString());
        Assert.Equal("payload_schema_violation", results[0].GetProperty("error").GetString());
        Assert.Equal("/id", results[0].GetProperty("pointer").GetString());

        Assert.Equal("accepted", results[1].GetProperty("status").GetString());

        Assert.Equal("rejected", results[2].GetProperty("status").GetString());
        Assert.Equal("payload_invalid", results[2].GetProperty("error").GetString());

        // Only the valid change persisted.
        Assert.Equal(1, await app.CountAsync("records", "account_id = @p", new { p = accountId }));
        Assert.Equal(good, await app.ScalarAsync<Guid>("SELECT id FROM records WHERE account_id = @p", new { p = accountId }));
    }

    // ---- 5. 410 on a revoked device ----------------------------------------

    [SkippableFact]
    public async Task Pull_RevokedDevice_Returns410_AndLiveDeviceStillWorks()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token1, accountId, device1) = await CreateSessionAsync(app, signer, "rev-sub", "rev@example.com", "iPhone");
        var (token2, _, device2) = await CreateSessionAsync(app, signer, "rev-sub", "rev@example.com", "iPad");

        Assert.Equal(accountId, await app.ScalarAsync<Guid>("SELECT account_id FROM devices WHERE id = @p", new { p = device2 }));
        Assert.NotEqual(device1, device2);

        var seeded = await PushBatchAsync(app.Client, token1, new[] { NewVehicleChange(Guid.NewGuid(), 0) });
        Assert.Equal(HttpStatusCode.OK, seeded.StatusCode);

        // Revoke device 1 (the account/devices endpoint lands in P4.9; here the
        // marker is set directly).
        await app.Db.ExecuteAsync("UPDATE devices SET revoked_at = now() WHERE id = @p", new { p = device1 });

        var revokedPull = await PullAsync(app.Client, token1, since: 0, limit: 500);
        Assert.Equal(HttpStatusCode.Gone, revokedPull.StatusCode);

        var revokedPush = await PushBatchAsync(app.Client, token1, new[] { NewVehicleChange(Guid.NewGuid(), 0) });
        Assert.Equal(HttpStatusCode.Gone, revokedPush.StatusCode);

        // The live device on the same account still pulls - revocation is per device.
        var livePull = await PullAsync(app.Client, token2, since: 0, limit: 500);
        Assert.Equal(HttpStatusCode.OK, livePull.StatusCode);
        Assert.Single(livePull.Records);
    }

    // ---- 6. 426 blocks push but not pull -----------------------------------

    [SkippableFact]
    public async Task Push_UpgradeRequired_Returns426_AndPullStillWorks()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "up-sub", "up@example.com");

        var stale = new JsonArray
        {
            Change(Guid.NewGuid(), 0, JsonNode.Parse(VehiclePayload(Guid.NewGuid()))!, schemaVersion: 0),
        };

        var response = await PushBatchAsync(app.Client, token, stale);
        Assert.Equal(HttpStatusCode.UpgradeRequired, response.StatusCode);

        // Nothing was written.
        Assert.Equal(0, await app.CountAsync("records", "account_id = @p", new { p = accountId }));

        // Pull still works - never lock a user out of their own data.
        var pull = await PullAsync(app.Client, token, since: 0, limit: 500);
        Assert.Equal(HttpStatusCode.OK, pull.StatusCode);
        Assert.Empty(pull.Records);
    }

    [SkippableFact]
    public async Task Push_SchemaVersionNewerThanServer_RejectedPerItem()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, _, _) = await CreateSessionAsync(app, signer, "new-sub", "new@example.com");

        var tooNew = new JsonArray
        {
            Change(Guid.NewGuid(), 0, JsonNode.Parse(VehiclePayload(Guid.NewGuid()))!, schemaVersion: 99),
        };

        var response = await PushBatchAsync(app.Client, token, tooNew);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var result = doc.RootElement.GetProperty("results")[0];
        Assert.Equal("rejected", result.GetProperty("status").GetString());
        Assert.Equal("schema_version_unsupported", result.GetProperty("error").GetString());
    }

    // ---- 7. SCN strictly monotonic under concurrency ------------------------

    [SkippableFact]
    public async Task Push_ConcurrentPushes_ProduceDistinctIncreasingScns()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, _, _) = await CreateSessionAsync(app, signer, "mono-sub", "mono@example.com");

        const int pushes = 25;
        var tasks = Enumerable.Range(0, pushes)
            .Select(_ => PushOneAsync(app.Client, token, NewVehicleChange(Guid.NewGuid(), 0)))
            .ToArray();

        var scns = await Task.WhenAll(tasks);

        Assert.Equal(Enumerable.Range(1, pushes).Select(i => (long)i).ToArray(), scns.OrderBy(x => x).ToArray());
    }

    // ---- 8. No payload, amount or token reaches a log -----------------------

    [SkippableFact]
    public async Task Push_Pull_NoPayloadAmountOrTokenReachesALog()
    {
        const string secretStation = "LUKOIL-secret-station-7f3a";
        const string secretAmount = "9876.54";
        const string secretToken = "tk_test_secret_abc123";

        var signer = new TestIdTokenSigner();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, writer);
        var (token, _, _) = await CreateSessionAsync(app, signer, "log-sub", "log@example.com");

        var fillUp = JsonNode.Parse(FillUpPayload(Guid.NewGuid(), secretStation, secretAmount, secretToken))!;
        var push = await PushBatchAsync(app.Client, token, new JsonArray { Change(Guid.NewGuid(), 0, fillUp, entityType: "fillUp") });
        Assert.Equal(HttpStatusCode.OK, push.StatusCode);

        var pull = await PullAsync(app.Client, token, since: 0, limit: 500);
        Assert.Equal(HttpStatusCode.OK, pull.StatusCode);

        var all = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The capture is proven non-empty: the sync event lines are present.
        Assert.Contains(lines, l => l.Contains("sync.push", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains("sync.pull", StringComparison.Ordinal));

        // Hard rule 12: none of the payload's contents reach any log line.
        Assert.DoesNotContain(secretStation, all, StringComparison.Ordinal);
        Assert.DoesNotContain(secretAmount, all, StringComparison.Ordinal);
        Assert.DoesNotContain(secretToken, all, StringComparison.Ordinal);
    }

    // ---- Bonus: clock skew clamp and forward-compat round trip --------------

    [SkippableFact]
    public async Task Push_ClientUpdatedAtFarFuture_IsClampedAndFlagged()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "clamp-sub", "clamp@example.com");

        var id = Guid.NewGuid();
        var future = DateTimeOffset.UtcNow.AddHours(48).ToString("O");
        var response = await PushBatchAsync(app.Client, token, new[]
        {
            Change(id, 0, JsonNode.Parse(VehiclePayload(id))!, clientUpdatedAt: future),
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var result = doc.RootElement.GetProperty("results")[0];
        Assert.Equal("accepted", result.GetProperty("status").GetString());
        Assert.True(result.GetProperty("clamped").GetBoolean());

        var stored = await app.ScalarAsync<DateTime>(
            "SELECT client_updated_at FROM records WHERE account_id = @p AND id = @id",
            new { p = accountId, id });
        var delta = DateTime.UtcNow - stored;
        Assert.True(delta < TimeSpan.FromMinutes(5) && delta > TimeSpan.FromMinutes(-5),
            $"clamped client_updated_at should be ~now, got {stored:O} (sent {future}).");
    }

    [SkippableFact]
    public async Task Push_UnknownEntityType_AcceptedAndRoundTripsThroughPull()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer);
        var (token, _, _) = await CreateSessionAsync(app, signer, "fwd-sub", "fwd@example.com");

        var id = Guid.NewGuid();
        var payload = JsonNode.Parse("""{ "treadDepthMm": 7, "season": "winter" }""")!;
        var response = await PushBatchAsync(app.Client, token, new JsonArray
        {
            Change(id, 0, payload, entityType: "tireset", schemaVersion: 1),
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using (var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync()))
        {
            Assert.Equal("accepted", doc.RootElement.GetProperty("results")[0].GetProperty("status").GetString());
        }

        var pull = await PullAsync(app.Client, token, since: 0, limit: 500);
        Assert.Equal(HttpStatusCode.OK, pull.StatusCode);
        var record = Assert.Single(pull.Records);
        Assert.Equal("tireset", record.EntityType);
        Assert.Equal(id, record.Id);
    }

    // ---- 9. PR.8: the request line carries the client's version and identity

    [SkippableFact]
    public async Task AuthenticatedPull_RequestLine_CarriesClientVersionAccountHashAndDeviceId()
    {
        var signer = new TestIdTokenSigner();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, writer);
        var (token, _, deviceId) = await CreateSessionAsync(app, signer, "scope-sub", "scope@example.com");

        // docs/LOGGING.md §2 L2 gate: an authenticated sync/pull request line
        // carries non-null clientVersion, accountHash, deviceId, schemaVersion.
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/sync/pull?since=0&limit=10");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add(LogScopeEnrichmentMiddleware.AppVersionHeader, "1.0.0+1");
        request.Headers.Add(LogScopeEnrichmentMiddleware.PlatformHeader, "ios");
        request.Headers.Add(LogScopeEnrichmentMiddleware.SchemaVersionHeader, "1");
        var response = await app.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var line = writer.JsonLines().RequestLine("/v1/sync/pull");
        Assert.Equal("1.0.0+1", line.Prop("clientVersion"));
        Assert.Equal("ios", line.Prop("clientPlatform"));
        Assert.False(string.IsNullOrWhiteSpace(line.Prop("accountHash")),
            "an authenticated request must resolve an accountHash");
        Assert.Equal(deviceId.ToString(), line.Prop("deviceId"));
        Assert.Equal("1", line.Prop("schemaVersion"));
        Assert.False(string.IsNullOrWhiteSpace(line.Prop("serverVersion")),
            "the server's own version field is renamed and populated");

        // The email must never appear anywhere, including this new path
        // (hard rule 12; the existing redaction sweep still applies).
        Assert.DoesNotContain("scope@example.com", string.Join('\n', lines), StringComparison.Ordinal);
    }

    // ---- helpers -----------------------------------------------------------

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
                // A SUCCESSFUL request line is Debug since 2026-09-02 (only
                // failures are Information). This test reads that line for its
                // correlation fields - the PR.8 guarantee is unchanged, only its
                // level moved - so the host captures at Debug.
                .UseSetting("Logging:LogLevel:Default", "Debug")
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

    private static JsonObject NewVehicleChange(Guid id, long baseScn)
        => Change(id, baseScn, JsonNode.Parse(VehiclePayload(id))!);

    private static JsonObject Change(
        Guid id,
        long baseScn,
        JsonNode payload,
        string entityType = "vehicle",
        int schemaVersion = 1,
        bool deleted = false,
        string? clientUpdatedAt = null)
    {
        return new JsonObject
        {
            ["id"] = id.ToString(),
            ["entityType"] = entityType,
            ["schemaVersion"] = schemaVersion,
            ["baseScn"] = baseScn,
            ["payload"] = payload.DeepClone(),
            ["clientUpdatedAt"] = clientUpdatedAt ?? PayloadTimestamp,
            ["deleted"] = deleted,
        };
    }

    private static async Task<HttpResponseMessage> PushBatchAsync(HttpClient client, string token, IEnumerable<JsonObject> changes)
        => await PushBatchAsync(client, token, new JsonArray(changes.Select(c => c.DeepClone()).ToArray()));

    private static async Task<HttpResponseMessage> PushBatchAsync(HttpClient client, string token, JsonArray changes)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/sync/push");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { changes });
        return await client.SendAsync(request);
    }

    private static async Task<long> PushOneAsync(HttpClient client, string token, JsonObject change)
    {
        var response = await PushBatchAsync(client, token, new[] { change });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var result = doc.RootElement.GetProperty("results")[0];
        Assert.Equal("accepted", result.GetProperty("status").GetString());
        return result.GetProperty("newScn").GetInt64();
    }

    private static async Task<long[]> AcceptedScnsAsync(HttpResponseMessage response)
    {
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("results")
            .EnumerateArray()
            .Select(r => r.GetProperty("newScn").GetInt64())
            .ToArray();
    }

    private static async Task<PullPage> PullAsync(HttpClient client, string token, long since, int limit)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"/v1/sync/pull?since={since}&limit={limit}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var response = await client.SendAsync(request);
        if (response.StatusCode != HttpStatusCode.OK)
        {
            return new PullPage(response.StatusCode, Array.Empty<PulledRecord>(), 0, false, 0, 0);
        }

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = doc.RootElement;
        var records = root.GetProperty("records").EnumerateArray()
            .Select(r => new PulledRecord(
                Guid.Parse(r.GetProperty("id").GetString()!),
                r.GetProperty("scn").GetInt64(),
                r.GetProperty("entityType").GetString()!))
            .ToArray();
        var policy = root.GetProperty("schemaPolicy");
        return new PullPage(
            response.StatusCode,
            records,
            root.GetProperty("nextSince").GetInt64(),
            root.GetProperty("more").GetBoolean(),
            policy.GetProperty("minSupported").GetInt32(),
            policy.GetProperty("current").GetInt32());
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

    private static string FillUpPayload(Guid id, string note, string amount, string token) => $$"""
        {
          "id": "{{id}}",
          "createdAt": "2026-08-22T12:10:05.000Z",
          "updatedAt": "2026-08-22T12:10:05.000Z",
          "vehicleId": "11111111-1111-7111-8111-111111111111",
          "date": "2026-08-22T12:10:00.000Z",
          "attachments": [],
          "provenance": { "tag": "manual" },
          "conflict": { "tag": "none" },
          "volumeL": 42.3,
          "fuelKind": "petrol95",
          "isFull": true,
          "crossCheck": { "tag": "verified" },
          "note": "{{note}}",
          "money": { "amount": "{{amount}}", "currency": "RUB", "homeCurrency": "RUB", "rateSource": "ecb" },
          "apiKey": "{{token}}"
        }
        """;

    private sealed record PulledRecord(Guid Id, long Scn, string EntityType);

    private sealed record PullPage(
        HttpStatusCode StatusCode,
        IReadOnlyList<PulledRecord> Records,
        long NextSince,
        bool More,
        int MinSupported,
        int Current);

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
