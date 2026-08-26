using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
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

namespace Tankbook.Api.Tests.Blobs;

/// <summary>
/// L2 tests for the blob pipeline (docs/API.md "Attachments", docs/SYNC.md
/// "Attachments: the blob pipeline") against real Postgres via Testcontainers.
/// The idToken verifier is the test signer and IBlobStorage is a recording
/// double - the bearer middleware, the repository, the quota/sweep/purge logic
/// and the HTTP surface are all real; only the external identity provider and
/// the object store are faked (docs/TESTING.md "mock the boundary").
/// </summary>
public class BlobEndpointTests : IClassFixture<PostgresFixture>
{
    private const long Image25Mb = 25L * 1024 * 1024;
    private const long Image26Mb = 26L * 1024 * 1024;
    private const long Pdf10Mb = 10L * 1024 * 1024;
    private const long Pdf11Mb = 11L * 1024 * 1024;

    private readonly PostgresFixture _fixture;

    public BlobEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- 1. Dedupe is per account ------------------------------------------

    [SkippableFact]
    public async Task Begin_Dedupe_IsPerAccount_NotGlobal()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (tokenA, accountA, _) = await CreateSessionAsync(app, signer, "dedupe-a", "a@example.com");
        var (tokenB, accountB, _) = await CreateSessionAsync(app, signer, "dedupe-b", "b@example.com");

        var sha = Sha('d');

        var firstA = await BeginAsync(app.Client, tokenA, sha, 1000, "image/jpeg");
        Assert.Equal(HttpStatusCode.OK, firstA.StatusCode);
        Assert.Equal("upload", (await firstA.Content.ReadFromJsonAsync<BlobBeginResponse>())!.Status);

        storage.Put(BlobKeys.Key(accountA, sha), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, tokenA, sha)).StatusCode);

        // Same account, same sha -> dedupe hit.
        var againA = await BeginAsync(app.Client, tokenA, sha, 1000, "image/jpeg");
        Assert.Equal("exists", (await againA.Content.ReadFromJsonAsync<BlobBeginResponse>())!.Status);

        // Different account, same sha -> not a hit; content addressing dedupes per account.
        var firstB = await BeginAsync(app.Client, tokenB, sha, 1000, "image/jpeg");
        Assert.Equal("upload", (await firstB.Content.ReadFromJsonAsync<BlobBeginResponse>())!.Status);

        storage.Put(BlobKeys.Key(accountB, sha), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, tokenB, sha)).StatusCode);

        Assert.Equal(1, await app.CountAsync("blobs", "account_id = @p", new { p = accountA }));
        Assert.Equal(1, await app.CountAsync("blobs", "account_id = @p", new { p = accountB }));
        Assert.Equal(2, await app.CountAsync("blobs"));
    }

    // ---- 2. Per-type size caps ---------------------------------------------

    [SkippableFact]
    public async Task Begin_SizeCaps_ArePerType_NotOneSharedLimit()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token, _, _) = await CreateSessionAsync(app, signer, "caps", "caps@example.com");

        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, Sha('1'), Image25Mb, "image/jpeg")).StatusCode);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await BeginAsync(app.Client, token, Sha('2'), Image26Mb, "image/jpeg")).StatusCode);

        // A 25 MB PDF would pass the image cap but must fail the PDF cap - the
        // boundary is per type, not one shared number.
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await BeginAsync(app.Client, token, Sha('3'), Image25Mb, "application/pdf")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, Sha('4'), Pdf10Mb, "application/pdf")).StatusCode);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await BeginAsync(app.Client, token, Sha('5'), Pdf11Mb, "application/pdf")).StatusCode);

        Assert.Equal(0, await app.CountAsync("blobs"));
    }

    // ---- 3. Content-type allow-list and shape ------------------------------

    [SkippableFact]
    public async Task Begin_DisallowedContentType_IsRefusedNot500()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token, _, _) = await CreateSessionAsync(app, signer, "ctype", "ctype@example.com");

        Assert.Equal(HttpStatusCode.UnsupportedMediaType, (await BeginAsync(app.Client, token, Sha('6'), 1000, "text/html")).StatusCode);
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, (await BeginAsync(app.Client, token, Sha('7'), 1000, "image/gif")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await BeginAsync(app.Client, token, "not-a-sha256", 1000, "image/jpeg")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await BeginAsync(app.Client, token, Sha('8'), -1, "image/jpeg")).StatusCode);
    }

    // ---- 4. Commit verifies the object and its size ------------------------

    [SkippableFact]
    public async Task Commit_WithoutUpload_NoRow()
    {
        var signer = new TestIdTokenSigner();
        await using var app = await StartAsync(signer, new RecordingBlobStorage());
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "no-upload", "nu@example.com");

        var sha = Sha('9');
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, sha, 1000, "image/jpeg")).StatusCode);

        var commit = await CommitAsync(app.Client, token, sha);
        Assert.Equal(HttpStatusCode.Conflict, commit.StatusCode);
        Assert.Equal(0, await app.CountAsync("blobs", "account_id = @p", new { p = accountId }));
    }

    [SkippableFact]
    public async Task Commit_SizeMismatch_NoRow()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "size-mismatch", "sm@example.com");

        var sha = Sha('e');
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, sha, 1000, "image/jpeg")).StatusCode);

        storage.Put(BlobKeys.Key(accountId, sha), 500);

        var commit = await CommitAsync(app.Client, token, sha);
        Assert.Equal(HttpStatusCode.Conflict, commit.StatusCode);
        Assert.Equal(0, await app.CountAsync("blobs", "account_id = @p", new { p = accountId }));
    }

    [SkippableFact]
    public async Task Commit_VerifiedObject_InsertsRowAndClearsPending()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "commit-ok", "ok@example.com");

        var sha = Sha('c');
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, sha, 1000, "image/jpeg")).StatusCode);

        storage.Put(BlobKeys.Key(accountId, sha), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, sha)).StatusCode);

        Assert.Equal(1, await app.CountAsync("blobs", "account_id = @p", new { p = accountId }));
        Assert.Equal(1000L, await app.ScalarAsync<long>("SELECT size_bytes FROM blobs WHERE account_id = @p AND sha256 = @s", new { p = accountId, s = sha }));
        Assert.Equal(0, await app.CountAsync("blob_pending", "account_id = @p", new { p = accountId }));
    }

    // ---- 5. Cross-account 404, no presigned URL minted ---------------------

    [SkippableFact]
    public async Task Get_CrossAccount_Returns404_AndNeverMintsAUrl()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (tokenA, accountA, _) = await CreateSessionAsync(app, signer, "owner", "owner@example.com");
        var (tokenB, _, _) = await CreateSessionAsync(app, signer, "intruder", "intruder@example.com");

        var sha = Sha('a');
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, tokenA, sha, 1000, "image/jpeg")).StatusCode);
        storage.Put(BlobKeys.Key(accountA, sha), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, tokenA, sha)).StatusCode);

        var foreign = await GetAsync(app.Client, tokenB, sha);
        Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);

        // The decisive half: no presigned GET was ever requested. A 404 that was
        // preceded by minting a URL has already leaked it into logs and traces.
        Assert.Empty(storage.DownloadUrls);
    }

    // ---- 6. Upload and download presign lifetimes differ -------------------

    [SkippableFact]
    public async Task Presign_UploadAndDownloadLifetimes_Differ()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "presign", "presign@example.com");

        var sha = Sha('b');
        var before = DateTimeOffset.UtcNow;
        var begin = await BeginAsync(app.Client, token, sha, 1000, "image/jpeg");
        Assert.Equal(HttpStatusCode.OK, begin.StatusCode);
        var body = (await begin.Content.ReadFromJsonAsync<BlobBeginResponse>())!;
        Assert.Equal("upload", body.Status);
        Assert.NotNull(body.Url);
        Assert.NotNull(body.ExpiresAt);

        // The begin response's expiry is ~15 minutes out.
        var uploadRemaining = body.ExpiresAt!.Value - before;
        Assert.True(uploadRemaining > TimeSpan.FromMinutes(14) && uploadRemaining < TimeSpan.FromMinutes(16),
            $"upload expires in {uploadRemaining}");

        storage.Put(BlobKeys.Key(accountId, sha), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, sha)).StatusCode);

        var get = await GetAsync(app.Client, token, sha);
        Assert.Equal(HttpStatusCode.Redirect, get.StatusCode);
        Assert.False(string.IsNullOrWhiteSpace(get.Headers.Location?.ToString()));

        // The two lifetimes are recorded separately and are not the same number.
        var uploadLifetime = Assert.Single(storage.UploadUrls).Lifetime;
        var downloadLifetime = Assert.Single(storage.DownloadUrls).Lifetime;
        Assert.NotEqual(uploadLifetime, downloadLifetime);
        Assert.True(uploadLifetime > TimeSpan.FromMinutes(14) && uploadLifetime < TimeSpan.FromMinutes(16),
            $"upload lifetime {uploadLifetime}");
        Assert.True(downloadLifetime > TimeSpan.FromMinutes(9) && downloadLifetime < TimeSpan.FromMinutes(11),
            $"download lifetime {downloadLifetime}");
    }

    // ---- 7. Quota is metered and enforced at begin -------------------------

    [SkippableFact]
    public async Task Begin_OverQuota_Returns429_AndCreatesNoRow()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage, quotaBytes: "2000");
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "quota", "quota@example.com");

        var s1 = Sha('a');
        var s2 = Sha('b');
        var s3 = Sha('c');

        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, s1, 1000, "image/jpeg")).StatusCode);
        storage.Put(BlobKeys.Key(accountId, s1), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, s1)).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, s2, 1000, "image/jpeg")).StatusCode);
        storage.Put(BlobKeys.Key(accountId, s2), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, s2)).StatusCode);

        // 2000 bytes used, quota 2000: one more byte overflows.
        var over = await BeginAsync(app.Client, token, s3, 1, "image/jpeg");
        Assert.Equal(HttpStatusCode.TooManyRequests, over.StatusCode);

        Assert.Equal(2, await app.CountAsync("blobs", "account_id = @p", new { p = accountId }));
        Assert.Equal(0, await app.CountAsync("blobs", "account_id = @p AND sha256 = @s", new { p = accountId, s = s3 }));
    }

    // ---- 8. Orphan sweep with surviving cases ------------------------------

    [SkippableFact]
    public async Task SweepOrphans_DeletesOnlyUnreferencedPastGrace()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (_, accountId, _) = await CreateSessionAsync(app, signer, "sweep", "sweep@example.com");

        var orphan = Sha('a');
        var live = Sha('b');
        var tombstoned = Sha('c');
        var old = DateTimeOffset.UtcNow.AddDays(-40);

        // Three blobs, all committed long ago (past the 30-day grace period).
        foreach (var sha in new[] { orphan, live, tombstoned })
        {
            var key = BlobKeys.Key(accountId, sha);
            storage.Put(key, 1000);
            await app.Db.ExecuteAsync(
                "INSERT INTO blobs (account_id, sha256, size_bytes, storage_ref, created_at) VALUES (@a, @s, 1000, @r, @c)",
                new { a = accountId, s = sha, r = key, c = old });
        }

        // A live record references 'live'; a record tombstoned one day ago references 'tombstoned'.
        await InsertRecordAsync(app, accountId, live, deleted: false, clientUpdatedAt: DateTimeOffset.UtcNow, scn: 1);
        await InsertRecordAsync(app, accountId, tombstoned, deleted: true, clientUpdatedAt: DateTimeOffset.UtcNow.AddDays(-1), scn: 2);

        using var scope = app.Services.CreateScope();
        var blobs = scope.ServiceProvider.GetRequiredService<BlobService>();
        var swept = await blobs.SweepOrphansAsync(accountId, CancellationToken.None);

        Assert.Equal(1, swept);

        // Index: only the orphan is gone.
        Assert.Equal(0, await app.CountAsync("blobs", "account_id = @p AND sha256 = @s", new { p = accountId, s = orphan }));
        Assert.Equal(1, await app.CountAsync("blobs", "account_id = @p AND sha256 = @s", new { p = accountId, s = live }));
        Assert.Equal(1, await app.CountAsync("blobs", "account_id = @p AND sha256 = @s", new { p = accountId, s = tombstoned }));

        // Storage: only the orphan's object was deleted.
        Assert.Contains(BlobKeys.Key(accountId, orphan), storage.DeletedKeys);
        Assert.True(storage.Objects.ContainsKey(BlobKeys.Key(accountId, live)));
        Assert.True(storage.Objects.ContainsKey(BlobKeys.Key(accountId, tombstoned)));
    }

    // ---- 9. Account deletion purges the whole prefix -----------------------

    [SkippableFact]
    public async Task PurgeAccount_RemovesIndexAndStorageObjects()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(signer, storage);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "purge", "purge@example.com");

        var s1 = Sha('1');
        var s2 = Sha('2');
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, s1, 1000, "image/jpeg")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await BeginAsync(app.Client, token, s2, 1000, "image/jpeg")).StatusCode);
        storage.Put(BlobKeys.Key(accountId, s1), 1000);
        storage.Put(BlobKeys.Key(accountId, s2), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, s1)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, s2)).StatusCode);

        using var scope = app.Services.CreateScope();
        var blobs = scope.ServiceProvider.GetRequiredService<BlobService>();
        var purged = await blobs.PurgeAccountAsync(accountId, CancellationToken.None);

        Assert.Equal(2, purged);
        Assert.Equal(0, await app.CountAsync("blobs", "account_id = @p", new { p = accountId }));
        Assert.DoesNotContain(BlobKeys.Key(accountId, s1), storage.Objects.Keys);
        Assert.DoesNotContain(BlobKeys.Key(accountId, s2), storage.Objects.Keys);
    }

    // ---- 10. No presigned URL or secret reaches a log ----------------------

    [SkippableFact]
    public async Task BlobFlow_NoPresignedUrlOrSecretReachesALog()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        await using var app = await StartAsync(signer, storage, writer);
        var (token, accountId, _) = await CreateSessionAsync(app, signer, "log-blob", "log-blob@example.com");

        var sha = Sha('e');
        var begin = await BeginAsync(app.Client, token, sha, 1000, "image/jpeg");
        Assert.Equal(HttpStatusCode.OK, begin.StatusCode);
        var beginUrl = (await begin.Content.ReadFromJsonAsync<BlobBeginResponse>())!.Url!;

        storage.Put(BlobKeys.Key(accountId, sha), 1000);
        Assert.Equal(HttpStatusCode.NoContent, (await CommitAsync(app.Client, token, sha)).StatusCode);

        var get = await GetAsync(app.Client, token, sha);
        Assert.Equal(HttpStatusCode.Redirect, get.StatusCode);
        var downloadUrl = get.Headers.Location!.ToString();

        var all = string.Join('\n', writer.Lines);

        // The log is non-empty and carries the blob events.
        Assert.Contains(lines, l => l.Contains("blob.begin", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains("blob.commit", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains("blob.get", StringComparison.Ordinal));

        // Hard rule 12: neither presigned URL (bearer credentials in a query
        // string) reaches any log line.
        Assert.DoesNotContain(beginUrl, all, StringComparison.Ordinal);
        Assert.DoesNotContain(downloadUrl, all, StringComparison.Ordinal);
        Assert.DoesNotContain("presign.invalid", all, StringComparison.Ordinal);
    }

    // ---- helpers -----------------------------------------------------------

    private static string Sha(char c) => new(c, 64);

    private async Task<TestApp> StartAsync(
        TestIdTokenSigner signer,
        RecordingBlobStorage storage,
        InMemoryLogWriter? writer = null,
        string? quotaBytes = null)
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
                if (quotaBytes is not null)
                {
                    b.UseSetting("Blob:QuotaBytes", quotaBytes);
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

    private static async Task<HttpResponseMessage> BeginAsync(HttpClient client, string token, string sha256, long size, string contentType)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/blobs/begin");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { sha256, size, contentType });
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> CommitAsync(HttpClient client, string token, string sha256)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/blobs/commit");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { sha256 });
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> GetAsync(HttpClient client, string token, string sha256)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"/v1/blobs/{sha256}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request);
    }

    private static async Task InsertRecordAsync(
        TestApp app,
        Guid accountId,
        string sha256,
        bool deleted,
        DateTimeOffset clientUpdatedAt,
        long scn)
    {
        await app.Db.ExecuteAsync(
            """
            INSERT INTO records (account_id, id, entity_type, schema_version, scn, payload, client_updated_at, deleted)
            VALUES (@a, @id, 'attachment', 1, @scn, @payload::jsonb, @updated, @deleted)
            """,
            new
            {
                a = accountId,
                id = Guid.NewGuid(),
                scn,
                payload = $@"{{ ""file"": {{ ""sha256"": ""{sha256}"" }} }}",
                updated = clientUpdatedAt,
                deleted,
            });
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
