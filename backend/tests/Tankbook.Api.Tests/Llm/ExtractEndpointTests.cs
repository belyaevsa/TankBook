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
using Tankbook.Api.Blobs;
using Tankbook.Api.Data;
using Tankbook.Api.Llm;
using Tankbook.Api.Logging;
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;

namespace Tankbook.Api.Tests.Llm;

/// <summary>
/// L2 tests for POST /v1/extract (docs/API.md "LLM gateway (Pro)") against real
/// Postgres via Testcontainers. The idToken verifier is the test signer, the
/// provider is a recording double, and object storage is a recording double -
/// the bearer middleware, the repository, the quota ledger, the metering and the
/// HTTP surface are all real; only the identity provider, the model and the
/// object store are faked (docs/TESTING.md "mock the boundary"). The clock is
/// pinned so "today" (the quota period) is deterministic.
/// </summary>
public class ExtractEndpointTests : IClassFixture<PostgresFixture>
{
    private const int MaxImageBytes = 4 * 1024 * 1024;

    private static readonly DateTimeOffset Now = new(2026, 8, 26, 12, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Period = new(2026, 8, 26);

    private readonly PostgresFixture _fixture;

    public ExtractEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static ExtractEndpointTests()
    {
        DapperTypeHandlers.Register();
    }

    // ---- 1. The 4 MB envelope cap is enforced before the provider is called --

    [SkippableFact]
    public async Task Extract_OversizeImage_IsRejectedBeforeTheProviderIsCalled()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        await using var app = await StartAsync(signer, provider);
        var (token, _, _) = await CreateSessionAsync(app, signer, "oversize", "oversize@example.com");
        await app.SetTierAsync(await app.AccountIdByEmailAsync("oversize@example.com"), "pro");

        // One byte over the 4 MB base64 cap. The content never matters: the cap
        // fires before decode, so the provider must not be called at all.
        var image = new string('A', MaxImageBytes + 1);
        var response = await ExtractAsync(app.Client, token, "receipt", image, null);

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        Assert.Equal(0, provider.CallCount);

        // And nothing was metered for a request that never reached the model.
        Assert.Equal(0, await app.CountAsync("llm_usage"));
    }

    // ---- 2. 402 (no allowance) and 429 (period spent) are distinct ----------

    [SkippableFact]
    public async Task Extract_NoAllowanceIs402_And_SpentAllowanceIs429()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        await using var app = await StartAsync(signer, provider);

        // An UNENTITLED tier - one absent from TierRequestsPerPeriod - has no
        // allowance at all -> 402.
        //
        // This used to use the free tier, which had an allowance of 0 until
        // 2026-09-03 (RV.4). Free now gets the 50/day the config document
        // advertises, so it is no longer an example of "no entitlement" - but the
        // DISTINCTION this test exists for is unchanged, and still worth pinning:
        // 402 means "your tier cannot do this at all" while 429 means "you have
        // used up this period", and a client shows different next steps for each
        // (docs/ERRORS.md).
        var (noneToken, noneAccount, _) = await CreateSessionAsync(app, signer, "none-user", "none@example.com");
        await app.SetTierAsync(noneAccount, "unentitled");
        var freeResponse = await ExtractAsync(app.Client, noneToken, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.PaymentRequired, freeResponse.StatusCode);

        // A pro account whose period allowance is already spent -> 429.
        var (proToken, proAccount, _) = await CreateSessionAsync(app, signer, "pro-user", "pro@example.com");
        await app.SetTierAsync(proAccount, "pro");
        await app.SeedUsageAsync(proAccount, Period, requests: 200, tokens: 0);
        var spentResponse = await ExtractAsync(app.Client, proToken, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.TooManyRequests, spentResponse.StatusCode);

        // The two codes are not the same, and neither call reached the model.
        Assert.NotEqual(freeResponse.StatusCode, spentResponse.StatusCode);
        Assert.Equal(0, provider.CallCount);
    }

    // ---- 3. A successful call is metered on the ledger row ------------------

    [SkippableFact]
    public async Task Extract_Success_MetersRequestsAndTokensOnTheLedgerRow()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, _) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal)
            {
                ["volume"] = new LlmField(43.61, 0.95),
            },
            "test-model",
            PromptTokens: 12,
            CompletionTokens: 7));

        await using var app = await StartAsync(signer, provider);
        var (token, account, _) = await CreateSessionAsync(app, signer, "meter", "meter@example.com");
        await app.SetTierAsync(account, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Assert the ledger row, not the response: requests and tokens land on the
        // right (account_id, period).
        var row = await app.ScalarAsync<(int Requests, long Tokens)>(
            "SELECT requests, tokens FROM llm_usage WHERE account_id = @p AND period = @d",
            new { p = account, d = Period });
        Assert.Equal(1, row.Requests);
        Assert.Equal(19L, row.Tokens);
    }

    // ---- 4. A provider failure does not bill --------------------------------

    [SkippableFact]
    public async Task Extract_ProviderFailure_DoesNotBillTheUser()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetFailure();

        await using var app = await StartAsync(signer, provider);
        var (token, account, _) = await CreateSessionAsync(app, signer, "fail", "fail@example.com");
        await app.SetTierAsync(account, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.BadGateway, response.StatusCode);

        // The billing rule: a provider failure is not metered - no ledger row.
        Assert.Equal(0, await app.CountAsync("llm_usage", "account_id = @p", new { p = account }));
        Assert.Equal(1, provider.CallCount);
    }

    // ---- 5. No image, base64 blob, or field value reaches a log line ---------

    [SkippableFact]
    public async Task Extract_NoImageOrFieldValueReachesALog()
    {
        var sentinel = "LEAKCANARY-STATION-0x9F42";
        var imageBytes = Encoding.UTF8.GetBytes("IMG-SENTINEL-7F3A");
        var imageBase64 = Convert.ToBase64String(imageBytes);

        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, _) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal)
            {
                ["station"] = new LlmField(sentinel, 0.4),
                ["volume"] = new LlmField(43.61, 0.9),
            },
            "test-model",
            5,
            3));

        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, provider, writer);
        var (token, account, _) = await CreateSessionAsync(app, signer, "logs", "logs@example.com");
        await app.SetTierAsync(account, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", imageBase64, null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var swept = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The extract event is present - the sweep is asserting an absence, not
        // an empty log.
        Assert.Contains(lines, l => l.Contains("llm.extract", StringComparison.Ordinal));

        // Hard rule 12: neither the image (base64 or decoded), nor a field value,
        // appears in any rendered line.
        Assert.DoesNotContain(imageBase64, swept, StringComparison.Ordinal);
        Assert.DoesNotContain("IMG-SENTINEL-7F3A", swept, StringComparison.Ordinal);
        Assert.DoesNotContain(sentinel, swept, StringComparison.Ordinal);
        Assert.DoesNotContain("43.61", swept, StringComparison.Ordinal);
    }

    // ---- 5b. RV.60: the usage counter is named as usage, never quota ---------

    [SkippableFact]
    public async Task Extract_SuccessLog_CountsRequestsUsedBeforeAndAfter_NotQuota()
    {
        // QuotaBefore=6 QuotaAfter=7 read as a quota INCREASING when the two
        // fields are a period-usage counter going up. The renamed fields must say
        // what they count - requests used before and after the metered call - and
        // the old names must be gone (a mutation back to Quota* fails this test).
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, provider, writer);
        var (token, account, _) = await CreateSessionAsync(app, signer, "usage-names", "usage-names@example.com");
        await app.SetTierAsync(account, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var logLines = writer.JsonLines().ToList();
        var extract = Assert.Single(logLines, l => l.Prop("event") == "llm.extract" && l.Prop("outcome") == "ok");

        // A fresh account: 0 requests used before the call, 1 after it.
        Assert.Equal("0", extract.Prop("requestsUsedBefore"));
        Assert.Equal("1", extract.Prop("requestsUsedAfter"));
        Assert.Null(extract.Prop("quotaBefore"));
        Assert.Null(extract.Prop("quotaAfter"));
    }

    // ---- 6. The prompt is stored only as the ledger's rendition, by sha256 --

    [SkippableFact]
    public async Task Extract_StoresThePromptOnlyAsTheLedgerRendition()
    {
        var sentinel = "IMG-PERSIST-SENTINEL-5A1E";
        var imageBytes = Encoding.UTF8.GetBytes(sentinel);
        var imageBase64 = Convert.ToBase64String(imageBytes);

        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, provider, storage: storage);
        var (token, account, _) = await CreateSessionAsync(app, signer, "persist", "persist@example.com");
        await app.SetTierAsync(account, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", imageBase64, null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // No blob index row and no pending row - the rendition is NOT part of the
        // attachment pipeline. It is stored directly in blob storage as the call
        // ledger's prompt (docs/SECURITY.md "LLM call ledger"), addressed by sha256.
        Assert.Equal(0, await app.CountAsync("blobs"));
        Assert.Equal(0, await app.CountAsync("blob_pending"));
        Assert.Empty(storage.UploadUrls);

        var expectedSha = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(imageBytes)).ToLowerInvariant();
        Assert.True(storage.ByteObjects.ContainsKey(LlmCallKeys.PromptKey(account, expectedSha)));

        // No image-carrying column exists anywhere in the schema. The one bytea
        // column that DOES exist is delivery_outbox.payload (RV.44) - the opaque
        // result the gateway could not hand back, never an image, so it is
        // excluded from the image check.
        Assert.Equal(0, await app.ScalarAsync<long>(
            "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND (column_name ILIKE '%image%' OR (data_type = 'bytea' AND NOT (table_name = 'delivery_outbox' AND column_name = 'payload')))"));

        // The filesystem: no file in the temp root or the app's own directory
        // tree carries the sentinel bytes or the base64 envelope.
        AssertNoFileCarries(sentinel, imageBase64);
    }

    // ---- 7. The response shape matches ExtractionMeta ------------------------

    [SkippableFact]
    public async Task Extract_Response_MatchesExtractionMeta_WithPerFieldConfidence()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        provider.SetHandler((_, _, _, _) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal)
            {
                ["volume"] = new LlmField(43.61, 0.95),
                ["unitPrice"] = new LlmField(1.884, 0.90),
                ["total"] = new LlmField(82.16, 0.85),
                // A low-confidence field must survive as a value plus a low number -
                // dropping it would silently convert "uncertain" into "absent".
                ["station"] = new LlmField("Circle K", 0.4),
            },
            "test-model",
            8,
            4));

        await using var app = await StartAsync(signer, provider);
        var (token, account, _) = await CreateSessionAsync(app, signer, "shape", "shape@example.com");
        await app.SetTierAsync(account, "pro");

        var response = await ExtractAsync(app.Client, token, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("cloud-fallback v1", doc.RootElement.GetProperty("pipeline").GetString());

        var fields = doc.RootElement.GetProperty("fields");
        Assert.Equal(43.61, fields.GetProperty("volume").GetProperty("value").GetDouble());
        Assert.Equal(0.95, fields.GetProperty("volume").GetProperty("confidence").GetDouble());
        Assert.Equal("Circle K", fields.GetProperty("station").GetProperty("value").GetString());
        Assert.Equal(0.4, fields.GetProperty("station").GetProperty("confidence").GetDouble());
    }

    // ---- 8. Quota is per account --------------------------------------------

    [SkippableFact]
    public async Task Extract_Quota_IsPerAccount_NotShared()
    {
        var signer = new TestIdTokenSigner();
        var provider = new RecordingLlmProvider();
        await using var app = await StartAsync(signer, provider);

        // Account A's allowance is spent; account B is untouched.
        var (tokenA, accountA, _) = await CreateSessionAsync(app, signer, "spent", "spent@example.com");
        await app.SetTierAsync(accountA, "pro");
        await app.SeedUsageAsync(accountA, Period, requests: 200, tokens: 0);

        var (tokenB, accountB, _) = await CreateSessionAsync(app, signer, "fresh", "fresh@example.com");
        await app.SetTierAsync(accountB, "pro");

        var spentA = await ExtractAsync(app.Client, tokenA, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.TooManyRequests, spentA.StatusCode);

        // B still extracts; the metered row lands on B, never on A.
        var okB = await ExtractAsync(app.Client, tokenB, "receipt", SmallImage(), null);
        Assert.Equal(HttpStatusCode.OK, okB.StatusCode);

        Assert.Equal(200, await app.ScalarAsync<int>("SELECT requests FROM llm_usage WHERE account_id = @p AND period = @d", new { p = accountA, d = Period }));
        Assert.Equal(1, await app.ScalarAsync<int>("SELECT requests FROM llm_usage WHERE account_id = @p AND period = @d", new { p = accountB, d = Period }));
    }

    // ---- helpers -------------------------------------------------------------

    private static string SmallImage() => Convert.ToBase64String("receipt"u8.ToArray());

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

        // The gateway now stores the prompt rendition in blob storage (the call
        // ledger, migration 015), so every extract test needs a storage double -
        // otherwise the real S3BlobStorage would be resolved and fail.
        var storageDouble = storage ?? new RecordingBlobStorage(new MutableTimeProvider(Now));

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

    private static async Task<HttpResponseMessage> ExtractAsync(
        HttpClient client,
        string token,
        string kind,
        string image,
        ExtractHints? hints)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/extract");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { kind, image, hints });
        return await client.SendAsync(request);
    }

    private static void AssertNoFileCarries(string sentinel, string base64)
    {
        foreach (var root in new[] { Path.GetTempPath(), AppContext.BaseDirectory })
        {
            var options = new EnumerationOptions
            {
                RecurseSubdirectories = root == AppContext.BaseDirectory,
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint | FileAttributes.System,
            };

            foreach (var path in Directory.EnumerateFiles(root, "*", options))
            {
                FileInfo info;
                try
                {
                    info = new FileInfo(path);
                }
                catch
                {
                    continue;
                }

                if (info.Length <= 0 || info.Length > MaxImageBytes)
                {
                    continue;
                }

                string text;
                try
                {
                    text = File.ReadAllText(path);
                }
                catch
                {
                    continue;
                }

                Assert.DoesNotContain(sentinel, text, StringComparison.Ordinal);
                Assert.DoesNotContain(base64, text, StringComparison.Ordinal);
            }
        }
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

        public async Task SetTierAsync(Guid accountId, string tier)
            => await Db.ExecuteAsync("UPDATE accounts SET llm_tier = @tier WHERE id = @id", new { tier, id = accountId });

        public async Task<Guid> AccountIdByEmailAsync(string email)
            => await Db.QuerySingleAsync<Guid>("SELECT id FROM accounts WHERE email = @email", new { email });

        public async Task SeedUsageAsync(Guid accountId, DateOnly period, int requests, long tokens)
            => await Db.ExecuteAsync(
                "INSERT INTO llm_usage (account_id, period, requests, tokens) VALUES (@a, @p, @r, @t)",
                new { a = accountId, p = period, r = requests, t = tokens });

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
