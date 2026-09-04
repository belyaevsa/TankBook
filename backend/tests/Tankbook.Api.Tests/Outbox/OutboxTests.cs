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
using Tankbook.Api.Account;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Data;
using Tankbook.Api.Llm;
using Tankbook.Api.Logging;
using Tankbook.Api.Outbox;
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;
using Tankbook.Api.Tests.Llm;

namespace Tankbook.Api.Tests.Outbox;

/// <summary>
/// L2 tests for the delivery outbox (migration 016, RV.44) against real
/// Postgres via Testcontainers. The identity provider, the model and the object
/// store are faked (docs/TESTING.md "mock the boundary"); the bearer
/// middleware, the repositories, the gateway service, the outbox service and
/// the HTTP surface are real. The clock is pinned so "today" (the quota period
/// and the retention cutoff) is deterministic.
///
/// The traps this suite is written against (docs/TASKS.md RV.44): asserting a
/// drain "succeeded" instead of asserting the row is gone; asserting an outbox
/// row exists without asserting its count; and testing only the enqueue path.
/// Every assertion here names a count or a byte, never "a thing happened".
/// </summary>
public class OutboxTests : IClassFixture<PostgresFixture>
{
    /// <summary>
    /// The app's TimeProvider is frozen here, and every retention cutoff is
    /// computed from it. Age rows with <c>Now.AddDays(-n)</c>, NEVER with SQL
    /// <c>now() - interval 'n days'</c>: that mixes Postgres's real wall clock
    /// into a comparison against this frozen instant, so the test passes only
    /// on 2026-09-03 and rots the day after (RV.55, four suites went red on
    /// 2026-09-04). Both sides of a cutoff must read the same clock.
    /// </summary>
    private static readonly DateTimeOffset Now = new(2026, 9, 3, 12, 0, 0, TimeSpan.Zero);

    private const decimal InputPrice = 0.0000025m;
    private const decimal OutputPrice = 0.00001m;
    private const long PromptTokens = 1000;
    private const long CompletionTokens = 500;

    private readonly PostgresFixture _fixture;

    public OutboxTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static OutboxTests()
    {
        DapperTypeHandlers.Register();
    }

    // ---- 1. A failed delivery enqueues exactly one row; a normal one none ----

    [SkippableFact]
    public async Task FailedDelivery_EnqueuesExactlyOneRow_NormalDeliveryEnqueuesNone()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal) { ["volume"] = new LlmField(43.61, 0.95) },
            model.ModelId,
            PromptTokens,
            CompletionTokens));

        await using var app = await StartAsync(signer, provider);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");
        var (_, accountId, deviceId) = await CreateSessionAsync(app, signer, "outbox-enqueue", "outbox-enqueue@example.com");
        await app.SetTierAsync(accountId, "pro");

        var service = app.Resolve<LlmService>();

        // Delivery fails: the request was aborted before the answer could be
        // handed back. The model still completed (server-side token), so the
        // answer is queued - exactly one row.
        var gone = new CancellationToken(canceled: true);
        var failed = await service.ExtractAsync(accountId, deviceId, "receipt", Image("receipt-one"), new ExtractHints(null, null, null), CaptureId(), gone);
        Assert.Equal(ExtractStatus.DeliveredViaOutbox, failed.Status);
        Assert.Equal(1, await app.CountAsync("delivery_outbox"));

        // A normal delivery returns the answer and writes NO outbox row - the
        // count stays 1, never 2. "A successful call writes nothing" is the half
        // people forget; without it the outbox silently doubles every answer.
        var delivered = await service.ExtractAsync(accountId, deviceId, "receipt", Image("receipt-two"), new ExtractHints(null, null, null), CaptureId(), CancellationToken.None);
        Assert.Equal(ExtractStatus.Ok, delivered.Status);
        Assert.Equal(1, await app.CountAsync("delivery_outbox"));
    }

    // ---- 2. Drain returns the payload; the ack deletes the row --------------

    [SkippableFact]
    public async Task Drain_ReturnsThePayload_AndTheAckDeletesTheRow_SecondDrainIsEmpty()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        await using var app = await StartAsync(signer, provider);
        var (token, accountId, deviceId) = await CreateSessionAsync(app, signer, "outbox-drain", "outbox-drain@example.com");

        var outbox = app.Resolve<OutboxService>();
        var captureId = CaptureId();
        var payload = OutboxPayload(captureId);
        await outbox.EnqueueAsync(accountId, deviceId, payload, CancellationToken.None);
        Assert.Equal(1, await app.CountAsync("delivery_outbox"));

        // Drain (read-only): the payload is returned, and the row is STILL there
        // (the ack is a separate call - at-least-once, not delete-on-read).
        var drained = await DrainAsync(app.Client, token);
        Assert.Equal(HttpStatusCode.OK, drained.StatusCode);
        var drainBody = await ReadAsync<OutboxDrainBody>(drained);
        var item = Assert.Single(drainBody.Items);
        Assert.Equal(1, await app.CountAsync("delivery_outbox"));

        // The payload round-trips: opaque base64 on the wire, and it decodes to
        // the correlation id and the fields the server stored without reading.
        var decoded = JsonDocument.Parse(Convert.FromBase64String(item.Payload));
        Assert.Equal(captureId, decoded.RootElement.GetProperty("captureId").GetGuid().ToString());
        Assert.True(decoded.RootElement.TryGetProperty("fields", out var fields));
        Assert.True(decoded.RootElement.TryGetProperty("pipeline", out _));

        // Ack the row: it is deleted, and the SECOND drain is empty - not merely
        // that the first drain "succeeded".
        var ack = await AckAsync(app.Client, token, item.Id);
        Assert.Equal(HttpStatusCode.NoContent, ack.StatusCode);
        Assert.Equal(0, await app.CountAsync("delivery_outbox"));

        var second = await DrainAsync(app.Client, token);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        var secondBody = await ReadAsync<OutboxDrainBody>(second);
        Assert.Empty(secondBody.Items);
    }

    // ---- 3. DELETE /account purges outbox rows; the ledger survives ----------

    [SkippableFact]
    public async Task AccountDeletion_PurgesOutboxRows_AndLeavesLedgerFieldsUnaffected()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal) { ["total"] = new LlmField(82.16, 0.9) },
            model.ModelId,
            PromptTokens,
            CompletionTokens,
            "RESPONSE-BODY",
            null));

        await using var app = await StartAsync(signer, provider);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");
        var (_, accountId, deviceId) = await CreateSessionAsync(app, signer, "outbox-del", "outbox-del@example.com");
        await app.SetTierAsync(accountId, "pro");

        var service = app.Resolve<LlmService>();

        // One successful call (ledger row, no outbox row) and one failed-delivery
        // call (another ledger row AND an outbox row).
        await service.ExtractAsync(accountId, deviceId, "receipt", Image("receipt-one"), new ExtractHints(null, null, null), CaptureId(), CancellationToken.None);
        await service.ExtractAsync(accountId, deviceId, "receipt", Image("receipt-two"), new ExtractHints(null, null, null), CaptureId(), new CancellationToken(canceled: true));

        Assert.Equal(2, await app.CountAsync("llm_calls"));
        Assert.Equal(1, await app.CountAsync("delivery_outbox"));

        // Tombstone the account past its grace period and run the purge pass.
        await app.Db.ExecuteAsync("UPDATE accounts SET deleted_at = @aged WHERE id = @p", new { aged = Now.AddDays(-31), p = accountId });
        var purge = app.Resolve<AccountPurgeService>();
        await purge.PurgeDueAccountsAsync(CancellationToken.None);

        // The outbox is purged - asserted by count, not by "the purge ran".
        Assert.Equal(0, await app.CountAsync("delivery_outbox"));

        // The ledger's own rows survive with their SURVIVING fields intact -
        // account_id, model, vendor, tokens, cost - while the content columns
        // are purged (RV.33: content is purged, the row and its ledger fields
        // survive). This is the same contract the existing ledger test pins.
        var ledger = (await app.Db.QueryAsync<(Guid AccountId, string ModelId, string Vendor, long PromptTokens, long CompletionTokens, decimal Cost, string? ResponseBody)>(
            "SELECT account_id, model_id, vendor, prompt_tokens, completion_tokens, cost, response_body FROM llm_calls WHERE account_id = @p ORDER BY created_at",
            new { p = accountId })).ToList();
        Assert.Equal(2, ledger.Count);
        var first = ledger[0];
        Assert.Equal(accountId, first.AccountId);
        Assert.Equal("test-model", first.ModelId);
        Assert.Equal("test-vendor", first.Vendor);
        Assert.Equal(PromptTokens, first.PromptTokens);
        Assert.Equal(0.0075m, first.Cost);
        // Content is purged; the surviving fields are not.
        Assert.Null(first.ResponseBody);
    }

    // ---- 4. The 30-day retention purge, both sides of the cutoff -------------

    [SkippableFact]
    public async Task RetentionPurge_DropsRowsPast30Days_AndKeepsOneInsideTheWindow()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        await using var app = await StartAsync(signer, provider);
        var (_, accountId, deviceId) = await CreateSessionAsync(app, signer, "outbox-ret", "outbox-ret@example.com");

        var outbox = app.Resolve<OutboxService>();
        await outbox.EnqueueAsync(accountId, deviceId, OutboxPayload(CaptureId()), CancellationToken.None);
        await outbox.EnqueueAsync(accountId, deviceId, OutboxPayload(CaptureId()), CancellationToken.None);

        var rows = (await app.Db.QueryAsync<Guid>("SELECT id FROM delivery_outbox ORDER BY created_at")).ToList();
        var oldId = rows[0];
        var recentId = rows[1];

        await app.Db.ExecuteAsync("UPDATE delivery_outbox SET created_at = @aged WHERE id = @p", new { aged = Now.AddDays(-31), p = oldId });
        await app.Db.ExecuteAsync("UPDATE delivery_outbox SET created_at = @aged WHERE id = @p", new { aged = Now.AddDays(-1), p = recentId });

        var purged = await outbox.PurgeDueAsync(CancellationToken.None);
        Assert.Equal(1, purged);

        Assert.Equal(0, await app.CountAsync("delivery_outbox", "id = @p", new { p = oldId }));
        Assert.Equal(1, await app.CountAsync("delivery_outbox", "id = @p", new { p = recentId }));
    }

    // ---- helpers -------------------------------------------------------------

    private static string CaptureId() => Guid.NewGuid().ToString();

    private static string Image(string content) => Convert.ToBase64String(Encoding.UTF8.GetBytes(content));

    private static byte[] OutboxPayload(string captureId)
        => JsonSerializer.SerializeToUtf8Bytes(new
        {
            captureId,
            fields = new { volume = new { value = 43.61, confidence = 0.95 } },
            pipeline = "cloud-fallback v1",
        });

    private static async Task SeedModelAsync(
        TestApp app,
        string modelId,
        string vendor,
        decimal inputPrice,
        decimal outputPrice)
        => await app.Db.ExecuteAsync(
            """
            INSERT INTO llm_models (model_id, vendor, input_price, output_price, currency, context_window, supports_thinking, effective_from)
            VALUES (@model, @vendor, @input, @output, 'USD', 128000, false, '2026-01-01')
            """,
            new { model = modelId, vendor, input = inputPrice, output = outputPrice });

    private async Task<TestApp> StartAsync(TestIdTokenSigner signer, RecordingLlmProvider provider)
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        var connectionString = db.ConnectionString;

        var storage = new RecordingBlobStorage(new MutableTimeProvider(Now));

        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:Postgres", connectionString);
                b.ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                    services.Replace(ServiceDescriptor.Singleton<ILlmProvider>(provider));
                    services.Replace(ServiceDescriptor.Singleton<TimeProvider>(new MutableTimeProvider(Now)));
                    services.Replace(ServiceDescriptor.Singleton<IBlobStorage>(storage));
                });
            });

        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        return new TestApp(factory, client, db, signer);
    }

    private static async Task<(string AccessToken, Guid AccountId, Guid DeviceId)> CreateSessionAsync(
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
        return (body!.AccessToken, body.AccountId, body.DeviceId);
    }

    private static Task<HttpResponseMessage> DrainAsync(HttpClient client, string token)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/v1/outbox");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client.SendAsync(request);
    }

    private static Task<HttpResponseMessage> AckAsync(HttpClient client, string token, Guid id)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, $"/v1/outbox/{id}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client.SendAsync(request);
    }

    private static async Task<T> ReadAsync<T>(HttpResponseMessage response)
    {
        var json = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
    }

    private sealed class OutboxDrainBody
    {
        public List<OutboxItemBody> Items { get; set; } = [];
    }

    private sealed class OutboxItemBody
    {
        public Guid Id { get; set; }

        public string Payload { get; set; } = string.Empty;
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

        public IServiceProvider Services => _factory.Services;

        public T Resolve<T>() where T : notnull
        {
            var scope = Services.CreateScope();
            return scope.ServiceProvider.GetRequiredService<T>();
        }

        public async Task SetTierAsync(Guid accountId, string tier)
            => await Db.ExecuteAsync("UPDATE accounts SET llm_tier = @tier WHERE id = @id", new { tier, id = accountId });

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
