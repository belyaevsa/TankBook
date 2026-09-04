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
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;

namespace Tankbook.Api.Tests.Llm;

/// <summary>
/// L2 tests for the LLM call ledger (migration 015, RV.33) against real
/// Postgres via Testcontainers. The idToken verifier is the test signer, the
/// provider is a recording double, and object storage is a recording double -
/// the bearer middleware, the repository, the quota ledger, the model
/// resolution, the recording and the HTTP surface are all real; only the
/// identity provider, the model and the object store are faked. The clock is
/// pinned so "today" (the quota period and the dictionary effective-from) is
/// deterministic.
/// </summary>
public class LlmCallLedgerTests : IClassFixture<PostgresFixture>
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
    private static readonly DateOnly Period = new(2026, 9, 3);

    private const decimal InputPrice = 0.0000025m;
    private const decimal OutputPrice = 0.00001m;
    private const long PromptTokens = 1000;
    private const long CompletionTokens = 500;

    // Dapper does not map snake_case columns to PascalCase properties by default,
    // so the ledger is read through explicit aliases (the repository convention).
    private const string CallColumns = """
        id AS Id,
        account_id AS AccountId,
        device_id AS DeviceId,
        kind AS Kind,
        model_id AS ModelId,
        vendor AS Vendor,
        outcome AS Outcome,
        category AS Category,
        prompt_tokens AS PromptTokens,
        completion_tokens AS CompletionTokens,
        thinking_enabled AS ThinkingEnabled,
        input_price_per_token AS InputPricePerToken,
        output_price_per_token AS OutputPricePerToken,
        cost AS Cost,
        currency AS Currency,
        prompt_sha256 AS PromptSha256,
        prompt_body AS PromptBody,
        response_body AS ResponseBody,
        thinking_body AS ThinkingBody,
        duration_ms AS DurationMs,
        created_at AS CreatedAt
        """;

    private readonly PostgresFixture _fixture;

    public LlmCallLedgerTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static LlmCallLedgerTests()
    {
        DapperTypeHandlers.Register();
    }

    // ---- 1. A successful call writes one row with every field --------------

    /// The end-to-end question the seed exists to answer: does a REAL receipt
    /// recognition, priced by the shipped baseline rather than by a fixture,
    /// record a real cost? Every other ledger test seeds its own model with
    /// invented prices, so they prove the arithmetic and say nothing about
    /// whether production would price a call at all - a table full of $0.00 is
    /// exactly the failure this would hide.
    ///
    /// Seeds NO model and NO setting: migration 018's baseline is what resolves.
    [SkippableFact]
    public async Task ARealRecognition_IsPricedByTheShippedSeed_NotZero()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal) { ["volume"] = new LlmField(43.61, 0.95) },
            model.ModelId,
            PromptTokens,
            CompletionTokens));
        await using var app = await StartAsync(signer, provider);

        var (token, accountId, _) = await CreateSessionAsync(app, signer, "seed-cost", "seed-cost@example.com");
        await app.SetTierAsync(accountId, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var row = await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId });
        var call = Assert.Single(row);

        // Resolved from the seed, not from a fallback and not from a fixture.
        Assert.Equal("deepseek-v4-flash-vision-exp", call.ModelId);
        Assert.Equal("deepseek", call.Vendor);

        // The published OpenRouter rates, snapshotted onto the row.
        Assert.Equal(0.0000002200m, call.InputPricePerToken);
        Assert.Equal(0.0000006600m, call.OutputPricePerToken);

        // 1000 x 0.00000022 + 500 x 0.00000066 = 0.00022 + 0.00033 = 0.00055.
        // Pinned to the literal AND to the product, so neither a wrong rate nor
        // a wrong formula can pass - "> 0" would sail through both.
        Assert.Equal(0.00055m, call.Cost);
        Assert.Equal(PromptTokens * 0.0000002200m + CompletionTokens * 0.0000006600m, call.Cost);
        Assert.NotEqual(0m, call.Cost);
    }

    [SkippableFact]
    public async Task SuccessfulCall_WritesOneRow_WithEveryFieldPopulated()
    {
        var responseSentinel = "RESPONSE-SENTINEL-0x71";
        var thinkingSentinel = "THINKING-SENTINEL-0x72";

        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal) { ["volume"] = new LlmField(43.61, 0.95) },
            model.ModelId,
            PromptTokens,
            CompletionTokens,
            responseSentinel,
            thinkingSentinel));

        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, provider, writer: writer);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice, supportsThinking: true);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (token, accountId, deviceId) = await CreateSessionAsync(app, signer, "ledger-ok", "ledger-ok@example.com");
        await app.SetTierAsync(accountId, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage());
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Exactly one row, and every field is asserted - not just that a row exists.
        var row = await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId });
        Assert.Single(row);

        var call = row[0];
        Assert.Equal(accountId, call.AccountId);
        Assert.Equal(deviceId, call.DeviceId);
        Assert.Equal("receipt", call.Kind);
        Assert.Equal("test-model", call.ModelId);
        Assert.Equal("test-vendor", call.Vendor);
        Assert.Equal("ok", call.Outcome);
        Assert.Equal("success", call.Category);
        Assert.Equal(PromptTokens, call.PromptTokens);
        Assert.Equal(CompletionTokens, call.CompletionTokens);
        Assert.True(call.ThinkingEnabled);
        Assert.Equal(InputPrice, call.InputPricePerToken);
        Assert.Equal(OutputPrice, call.OutputPricePerToken);
        Assert.Equal("USD", call.Currency.Trim());
        Assert.Equal(responseSentinel, call.ResponseBody);
        Assert.Equal(thinkingSentinel, call.ThinkingBody);
        Assert.NotNull(call.PromptSha256);

        // The cost is the exact product of token counts and the snapshot prices -
        // pinned to the literal, not a "> 0" that a 10000x price bug would pass.
        Assert.Equal(0.0075m, call.Cost);
        Assert.Equal(PromptTokens * InputPrice + CompletionTokens * OutputPrice, call.Cost);

        // Hard rule 12: the response and thinking bodies are stored in the table
        // but never reach a log line.
        var all = string.Join('\n', lines).WithoutMachineFields();
        Assert.DoesNotContain(responseSentinel, all, StringComparison.Ordinal);
        Assert.DoesNotContain(thinkingSentinel, all, StringComparison.Ordinal);
    }

    // ---- 2. A failed call writes one row with its error category ------------

    [SkippableFact]
    public async Task FailedCall_WritesOneRow_WithErrorCategory()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetFailure();

        await using var app = await StartAsync(signer, provider);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (token, accountId, _) = await CreateSessionAsync(app, signer, "ledger-fail", "ledger-fail@example.com");
        await app.SetTierAsync(accountId, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage());
        Assert.Equal(HttpStatusCode.BadGateway, response.StatusCode);

        var row = await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId });
        Assert.Single(row);

        var call = row[0];
        Assert.Equal("provider_failed", call.Outcome);
        Assert.Equal("error", call.Category);
        Assert.Equal(0, call.PromptTokens);
        Assert.Equal(0, call.CompletionTokens);
        Assert.Equal(0m, call.Cost);
        Assert.Null(call.ResponseBody);
        Assert.NotNull(call.PromptSha256);
    }

    // ---- 3. Account deletion purges content, keeps the ledger ---------------

    [SkippableFact]
    public async Task AccountDeletion_RemovesBlobAndBodies_RowAndLedgerFieldsSurvive()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal) { ["total"] = new LlmField(82.16, 0.9) },
            model.ModelId,
            PromptTokens,
            CompletionTokens,
            "RESPONSE-BODY",
            "THINKING-BODY"));

        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, provider, storage: storage);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice, supportsThinking: true);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (token, accountId, _) = await CreateSessionAsync(app, signer, "ledger-del", "ledger-del@example.com");
        await app.SetTierAsync(accountId, "pro");
        await ExtractAsync(app.Client, token, "receipt", SmallImage());

        var before = (await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId })).Single();
        Assert.NotNull(before.ResponseBody);
        Assert.True(storage.ByteObjects.ContainsKey(LlmCallKeys.PromptKey(accountId, before.PromptSha256!)));

        // Tombstone the account past its grace period and run the purge pass.
        await app.Db.ExecuteAsync("UPDATE accounts SET deleted_at = @aged WHERE id = @p", new { aged = Now.AddDays(-31), p = accountId });
        using var scope = app.Services.CreateScope();
        var purge = scope.ServiceProvider.GetRequiredService<AccountPurgeService>();
        await purge.PurgeDueAccountsAsync(CancellationToken.None);

        // The rendition blob is gone - asserted by fetch-miss, not by a flag.
        Assert.False(storage.ByteObjects.ContainsKey(LlmCallKeys.PromptKey(accountId, before.PromptSha256!)));

        // The row survives with the ledger fields and the sha256 reference intact,
        // while the bodies are purged.
        var after = (await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId })).Single();
        Assert.Equal(accountId, after.AccountId);
        Assert.Equal("test-model", after.ModelId);
        Assert.Equal("test-vendor", after.Vendor);
        Assert.Equal(PromptTokens, after.PromptTokens);
        Assert.Equal(CompletionTokens, after.CompletionTokens);
        Assert.Equal(0.0075m, after.Cost);
        Assert.Equal(before.PromptSha256, after.PromptSha256);
        Assert.Null(after.ResponseBody);
        Assert.Null(after.ThinkingBody);
        Assert.Null(after.PromptBody);
    }

    // ---- 4. The price snapshot is immutable --------------------------------

    [SkippableFact]
    public async Task SnapshotInvariant_ChangingDictionaryPrice_DoesNotChangeRecordedCost()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal),
            model.ModelId,
            PromptTokens,
            CompletionTokens));

        await using var app = await StartAsync(signer, provider);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (token, accountId, _) = await CreateSessionAsync(app, signer, "ledger-snap", "ledger-snap@example.com");
        await app.SetTierAsync(accountId, "pro");
        await ExtractAsync(app.Client, token, "receipt", SmallImage());

        var recorded = (await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId })).Single();
        Assert.Equal(0.0075m, recorded.Cost);

        // A price correction: a NEW dictionary row effective later, higher prices.
        await app.Db.ExecuteAsync(
            "INSERT INTO llm_models (model_id, vendor, input_price, output_price, currency, context_window, supports_thinking, effective_from) VALUES ('test-model', 'test-vendor', 0.0001, 0.0004, 'USD', 128000, false, '2026-09-03')");

        // Re-read: the recorded cost is unchanged - the row snapshotted the price
        // it paid rather than pointing at the dictionary (hard rule 3's logic).
        var reread = (await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p", new { p = accountId })).Single();
        Assert.Equal(0.0075m, reread.Cost);
        Assert.Equal(InputPrice, reread.InputPricePerToken);
        Assert.Equal(OutputPrice, reread.OutputPricePerToken);
    }

    // ---- 5. The 30-day content purge, both sides of the cutoff --------------

    [SkippableFact]
    public async Task RetentionPurge_DropsContentPast30Days_AndKeepsOneInsideTheWindow()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, model) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal),
            model.ModelId,
            PromptTokens,
            CompletionTokens,
            "RESPONSE-BODY",
            null));

        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, provider, storage: storage);
        await SeedModelAsync(app, "test-model", "test-vendor", InputPrice, OutputPrice);
        await app.Db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'test-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (token, accountId, _) = await CreateSessionAsync(app, signer, "ledger-ret", "ledger-ret@example.com");
        await app.SetTierAsync(accountId, "pro");

        await ExtractAsync(app.Client, token, "receipt", Image("receipt-one"));
        await ExtractAsync(app.Client, token, "receipt", Image("receipt-two"));
        var rows = await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE account_id = @p ORDER BY created_at", new { p = accountId });

        var oldId = rows[0].Id;
        var recentId = rows[1].Id;

        await app.Db.ExecuteAsync("UPDATE llm_calls SET created_at = @aged WHERE id = @p", new { aged = Now.AddDays(-31), p = oldId });
        await app.Db.ExecuteAsync("UPDATE llm_calls SET created_at = @aged WHERE id = @p", new { aged = Now.AddDays(-1), p = recentId });

        using var scope = app.Services.CreateScope();
        var purge = scope.ServiceProvider.GetRequiredService<LlmCallPurgeService>();
        var purged = await purge.PurgeDueAsync(CancellationToken.None);

        Assert.Equal(1, purged);

        // The survivor keeps its content and its rendition.
        var recent = (await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE id = @p", new { p = recentId })).Single();
        Assert.Equal("RESPONSE-BODY", recent.ResponseBody);
        Assert.True(storage.ByteObjects.ContainsKey(LlmCallKeys.PromptKey(accountId, recent.PromptSha256!)));

        // The old call's content is purged, but the row and its ledger survive.
        var old = (await app.QueryAsync<LlmCallRow>(
            $"SELECT {CallColumns} FROM llm_calls WHERE id = @p", new { p = oldId })).Single();
        Assert.Null(old.ResponseBody);
        Assert.Equal(0.0075m, old.Cost);
        Assert.NotNull(old.PromptSha256);
        Assert.NotEqual(old.PromptSha256, recent.PromptSha256);
        Assert.False(storage.ByteObjects.ContainsKey(LlmCallKeys.PromptKey(accountId, old.PromptSha256!)));
    }

    // ---- helpers -------------------------------------------------------------

    private static string SmallImage() => Image("receipt");

    private static string Image(string content) => Convert.ToBase64String(Encoding.UTF8.GetBytes(content));

    private static async Task SeedModelAsync(
        TestApp app,
        string modelId,
        string vendor,
        decimal inputPrice,
        decimal outputPrice,
        bool supportsThinking = false)
        => await app.Db.ExecuteAsync(
            """
            INSERT INTO llm_models (model_id, vendor, input_price, output_price, currency, context_window, supports_thinking, effective_from)
            VALUES (@model, @vendor, @input, @output, 'USD', 128000, @thinking, '2026-01-01')
            """,
            new { model = modelId, vendor, input = inputPrice, output = outputPrice, thinking = supportsThinking });

    private async Task<TestApp> StartAsync(
        TestIdTokenSigner signer,
        RecordingLlmProvider provider,
        InMemoryLogWriter? writer = null,
        RecordingBlobStorage? storage = null)
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        var connectionString = db.ConnectionString;

        var storageDouble = storage ?? new RecordingBlobStorage(new MutableTimeProvider(Now));

        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:Postgres", connectionString);
                b.UseSetting("Logging:LogLevel:Default", "Debug");
                b.ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IIdTokenVerifier>(signer.Verifier));
                    services.Replace(ServiceDescriptor.Singleton<ILlmProvider>(provider));
                    services.Replace(ServiceDescriptor.Singleton<TimeProvider>(new MutableTimeProvider(Now)));
                    services.Replace(ServiceDescriptor.Singleton<IBlobStorage>(storageDouble));
                    if (writer is not null)
                    {
                        services.Replace(ServiceDescriptor.Singleton<ILogWriter>(writer));
                    }
                });
            });

        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        return new TestApp(factory, client, db, signer, provider, storageDouble);
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

    private static async Task<HttpResponseMessage> ExtractAsync(HttpClient client, string token, string kind, string image)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/extract");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { kind, image });
        return await client.SendAsync(request);
    }

    private sealed class LlmCallRow
    {
        public Guid Id { get; set; }

        public Guid AccountId { get; set; }

        public Guid? DeviceId { get; set; }

        public string Kind { get; set; } = string.Empty;

        public string ModelId { get; set; } = string.Empty;

        public string Vendor { get; set; } = string.Empty;

        public string Outcome { get; set; } = string.Empty;

        public string Category { get; set; } = string.Empty;

        public long PromptTokens { get; set; }

        public long CompletionTokens { get; set; }

        public bool ThinkingEnabled { get; set; }

        public decimal InputPricePerToken { get; set; }

        public decimal OutputPricePerToken { get; set; }

        public decimal Cost { get; set; }

        public string Currency { get; set; } = string.Empty;

        public string? PromptSha256 { get; set; }

        public string? PromptBody { get; set; }

        public string? ResponseBody { get; set; }

        public string? ThinkingBody { get; set; }

        public long DurationMs { get; set; }

        public DateTime CreatedAt { get; set; }
    }

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;
        private readonly HttpClient _client;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db, TestIdTokenSigner signer, RecordingLlmProvider provider, RecordingBlobStorage storage)
        {
            _factory = factory;
            _client = client;
            Db = db;
            Signer = signer;
            Provider = provider;
            Storage = storage;
        }

        public HttpClient Client => _client;

        public NpgsqlConnection Db { get; }

        public TestIdTokenSigner Signer { get; }

        public RecordingLlmProvider Provider { get; }

        public RecordingBlobStorage Storage { get; }

        public IServiceProvider Services => _factory.Services;

        public async Task SetTierAsync(Guid accountId, string tier)
            => await Db.ExecuteAsync("UPDATE accounts SET llm_tier = @tier WHERE id = @id", new { tier, id = accountId });

        public async Task<IReadOnlyList<T>> QueryAsync<T>(string sql, object? param = null)
            => (await Db.QueryAsync<T>(sql, param)).ToList();

        public async ValueTask DisposeAsync()
        {
            _client.Dispose();
            await Db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
