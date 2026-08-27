using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Npgsql;
using Tankbook.Api.Account;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Data;
using Tankbook.Api.Import;
using Tankbook.Api.Logging;
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;

namespace Tankbook.Api.Tests.Import;

/// <summary>
/// L2 tests for the import surface (docs/API.md "Import parsing", docs/SECURITY.md
/// "Import files at rest") against real Postgres via Testcontainers. The parser,
/// the repositories, the storage wiring and the HTTP surface are real;
/// IBlobStorage is a recording double (docs/TESTING.md "mock the boundary") so
/// the stored file and result are assertable without a running S3/MinIO. Every
/// test parses the committed real export, never a synthetic CSV.
/// </summary>
public class ImportEndpointTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public ImportEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    // ---- works signed out, and nothing is committed ------------------------

    [SkippableFact]
    public async Task ParseFuelCsv_WorksSignedOut_AndCommitsNothing()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        using var response = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", deviceId);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = ParseBody(await response.Content.ReadAsStringAsync());

        // The envelope: importId, format, scope, and the candidate count of the
        // real file (513 data rows, header taken from line 2, ';' delimiter).
        Assert.Equal("mfm", body.GetProperty("format").GetString());
        Assert.Equal("vehicle", body.GetProperty("scope").GetString());
        Assert.Equal(513, body.GetProperty("candidates").GetArrayLength());

        var ambiguities = body.GetProperty("ambiguities");
        Assert.Contains(ambiguities.EnumerateArray(), a => a.GetProperty("kind").GetString() == "dateFormat");
        Assert.Contains(ambiguities.EnumerateArray(), a => a.GetProperty("kind").GetString() == "currency");

        // Hard rule 9: the parse commits nothing. No account, no domain rows.
        Assert.Equal(0, await app.CountAsync("accounts"));
        Assert.Equal(0, await app.CountAsync("records"));
        Assert.Equal(1, await app.CountAsync("import_parses"));

        // The file and its result are stored (docs/SECURITY.md) under the
        // device identity - the signed-out shape.
        var importId = body.GetProperty("importId").GetGuid();
        Assert.True(storage.ByteObjects.ContainsKey(ImportKeys.FileKey(deviceId, importId)));
        Assert.True(storage.ByteObjects.ContainsKey(ImportKeys.ResultKey(deviceId, importId)));
    }

    [SkippableFact]
    public async Task Parse_WithNoBearerTokenAtAll_StillWorks()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/import/parse");
        request.Headers.TryAddWithoutValidation("X-Device-Id", deviceId.ToString());
        request.Content = BuildMultipart("mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv");

        using var response = await app.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(request.Headers.Authorization);
    }

    // ---- storage: GET and DELETE the stored parse --------------------------

    [SkippableFact]
    public async Task StoredParse_GetReturnsIt_DeleteRemovesIt()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        var parse = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", deviceId);
        var body = ParseBody(await parse.Content.ReadAsStringAsync());
        var importId = body.GetProperty("importId").GetGuid();

        // GET re-reads the stored parse so a review can be resumed.
        using var get = await GetImportAsync(app.Client, importId);
        Assert.Equal(HttpStatusCode.OK, get.StatusCode);
        var getBody = ParseBody(await get.Content.ReadAsStringAsync());
        Assert.Equal(importId, getBody.GetProperty("importId").GetGuid());
        Assert.Equal(513, getBody.GetProperty("candidates").GetArrayLength());

        // DELETE drops it early (docs/JOURNEYS.md F6a: cancel deletes the file).
        using var delete = await DeleteImportAsync(app.Client, importId);
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        Assert.False(storage.ByteObjects.ContainsKey(ImportKeys.FileKey(deviceId, importId)));
        Assert.False(storage.ByteObjects.ContainsKey(ImportKeys.ResultKey(deviceId, importId)));

        // The second DELETE is idempotent; GET after delete is a 404.
        using var deleteAgain = await DeleteImportAsync(app.Client, importId);
        Assert.Equal(HttpStatusCode.NoContent, deleteAgain.StatusCode);
        using var getAfter = await GetImportAsync(app.Client, importId);
        Assert.Equal(HttpStatusCode.NotFound, getAfter.StatusCode);
    }

    // ---- the 30-day purge, both sides of the cutoff ------------------------

    [SkippableFact]
    public async Task Purge_DropsAParsePast30Days_AndKeepsOneInsideTheWindow()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        var parseOld = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", deviceId);
        var oldId = ParseBody(await parseOld.Content.ReadAsStringAsync()).GetProperty("importId").GetGuid();
        var parseRecent = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.CostsCsv), "costs.csv", deviceId);
        var recentId = ParseBody(await parseRecent.Content.ReadAsStringAsync()).GetProperty("importId").GetGuid();

        // Place the old parse 31 days back and the recent one 1 day back.
        await app.Db.ExecuteAsync("UPDATE import_parses SET created_at = now() - interval '31 days' WHERE id = @p", new { p = oldId });
        await app.Db.ExecuteAsync("UPDATE import_parses SET created_at = now() - interval '1 day' WHERE id = @p", new { p = recentId });

        using var scope = app.Services.CreateScope();
        var purge = scope.ServiceProvider.GetRequiredService<ImportPurgeService>();
        var purged = await purge.PurgeDueImportsAsync(CancellationToken.None);

        Assert.Equal(1, purged);

        // The survivor is the half that matters: the recent parse is intact in
        // the index and in storage.
        Assert.Equal(1, await app.CountAsync("import_parses", "id = @p", new { p = recentId }));
        Assert.True(storage.ByteObjects.ContainsKey(ImportKeys.FileKey(deviceId, recentId)));
        Assert.True(storage.ByteObjects.ContainsKey(ImportKeys.ResultKey(deviceId, recentId)));

        // The old parse is gone from the index and from storage.
        Assert.Equal(0, await app.CountAsync("import_parses", "id = @p", new { p = oldId }));
        Assert.False(storage.ByteObjects.ContainsKey(ImportKeys.FileKey(deviceId, oldId)));
        Assert.False(storage.ByteObjects.ContainsKey(ImportKeys.ResultKey(deviceId, oldId)));
    }

    [SkippableFact]
    public async Task PurgeTimer_IsNotRegisteredInTheTestHost()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);

        // Tests drive ImportPurgeService.PurgeDueImportsAsync directly, never
        // the clock - the same reason the account-purge timer is gated.
        Assert.DoesNotContain(app.Services.GetServices<IHostedService>(), h => h is ImportPurgeHostedService);
    }

    // ---- account deletion deletes these too (docs/SECURITY.md) --------------

    [SkippableFact]
    public async Task AccountPurge_DeletesTheAccountsStoredImports()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage, accountDeletionGraceDays: 1, signer: signer);
        var (token, accountId) = await CreateSessionAsync(app, signer);

        using var parseResponse = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", Guid.NewGuid(), token);
        Assert.Equal(HttpStatusCode.OK, parseResponse.StatusCode);
        var importId = ParseBody(await parseResponse.Content.ReadAsStringAsync()).GetProperty("importId").GetGuid();

        // The parse was stored under the account, not the device.
        Assert.Equal(1, await app.CountAsync("import_parses", "id = @p AND account_id = @a", new { p = importId, a = accountId }));
        Assert.True(storage.ByteObjects.ContainsKey(ImportKeys.FileKey(accountId, importId)));

        // Tombstone the account past its grace period and run the purge pass.
        await app.Db.ExecuteAsync("UPDATE accounts SET deleted_at = now() - interval '2 days' WHERE id = @p", new { p = accountId });
        using var scope = app.Services.CreateScope();
        var purge = scope.ServiceProvider.GetRequiredService<AccountPurgeService>();
        await purge.PurgeDueAccountsAsync(CancellationToken.None);

        // Deleting the account deletes its imports too (docs/SECURITY.md
        // "Deleting the account deletes these"): row and objects are both gone.
        Assert.Equal(0, await app.CountAsync("import_parses", "id = @p", new { p = importId }));
        Assert.False(storage.ByteObjects.ContainsKey(ImportKeys.FileKey(accountId, importId)));
        Assert.False(storage.ByteObjects.ContainsKey(ImportKeys.ResultKey(accountId, importId)));
    }

    // ---- logs carry shape only ---------------------------------------------

    [SkippableFact]
    public async Task Parse_LogsCarryShapeOnly_NeverFixtureValues()
    {
        var lines = new List<string>();
        var writer = new InMemoryLogWriter(lines);
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage, writer);
        var deviceId = Guid.NewGuid();

        using var fuel = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", deviceId);
        Assert.Equal(HttpStatusCode.OK, fuel.StatusCode);
        using var costs = await ParseAsync(app.Client, "mfm", MfmFixture.ReadAllBytes(MfmFixture.CostsCsv), "costs.csv", deviceId);
        Assert.Equal(HttpStatusCode.OK, costs.StatusCode);

        var all = string.Join('\n', writer.Lines).WithoutMachineFields();

        // The pipeline captured the parse events (not an empty sweep).
        var importParseLines = writer.Lines.Count(l => l.Contains("import.parse", StringComparison.Ordinal));
        Assert.True(importParseLines >= 2, $"expected import.parse lines, saw {importParseLines}");

        // Hard rule 12: shape only - format, file kind, counts. No station,
        // note, amount, odometer or vehicle name from the fixture.
        Assert.DoesNotContain("Volvo", all, StringComparison.Ordinal);
        Assert.DoesNotContain("125.22", all, StringComparison.Ordinal);
        Assert.DoesNotContain("121727", all, StringComparison.Ordinal);
        Assert.DoesNotContain("Замена колес зима", all, StringComparison.Ordinal);
        Assert.DoesNotContain("8/24/2026", all, StringComparison.Ordinal);
        Assert.DoesNotContain("M/D/YYYY", all, StringComparison.Ordinal);
    }

    // ---- GET /import/formats: server-driven, ETag'd ------------------------

    [SkippableFact]
    public async Task Formats_IsPublic_Etagged_AndListsMfm()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        using var client = app.Client;

        using (var request = new HttpRequestMessage(HttpMethod.Get, "/v1/import/formats"))
        {
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.Null(request.Headers.Authorization);
            var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
            var formats = body.EnumerateArray().Select(f => f.GetProperty("id").GetString()!).ToArray();
            Assert.Contains("mfm", formats);
            var etag = response.Headers.ETag!.Tag;

            // A matching If-None-Match answers 304.
            using var conditional = new HttpRequestMessage(HttpMethod.Get, "/v1/import/formats");
            conditional.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(etag, isWeak: false));
            using var second = await client.SendAsync(conditional);
            Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
        }
    }

    // ---- the error statuses -------------------------------------------------

    [SkippableFact]
    public async Task UnknownOrMissingFormat_Is415()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        using var unknown = await ParseAsync(app.Client, "not-a-format", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", deviceId);
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, unknown.StatusCode);

        using var missing = await ParseAsync(app.Client, null, MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv", deviceId);
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, missing.StatusCode);
    }

    [SkippableFact]
    public async Task FileLargerThan8MB_Is413()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        var oversized = new byte[8 * 1024 * 1024 + 1];
        using var response = await ParseAsync(app.Client, "mfm", oversized, "huge.csv", deviceId);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }

    [SkippableFact]
    public async Task AFileThatIsNotAnMfmExport_Is422()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        var notMfm = Encoding.UTF8.GetBytes("date,volume,price\n1,2,3\n");
        using var response = await ParseAsync(app.Client, "mfm", notMfm, "some.csv", deviceId);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
    }

    [SkippableFact]
    public async Task SignedOutWithoutADeviceIdentity_Is400()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/import/parse")
        {
            Content = BuildMultipart("mfm", MfmFixture.ReadAllBytes(MfmFixture.FuelCsv), "fuel.csv"),
        };
        using var response = await app.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ---- helpers -----------------------------------------------------------

    private async Task<TestApp> StartAsync(RecordingBlobStorage storage, InMemoryLogWriter? writer = null, int? accountDeletionGraceDays = null, TestIdTokenSigner? signer = null)
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
                if (accountDeletionGraceDays is not null)
                {
                    b.UseSetting("Account:DeletionGraceDays", accountDeletionGraceDays.Value.ToString());
                }

                b.ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<IBlobStorage>(storage));
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

    private static async Task<(string AccessToken, Guid AccountId)> CreateSessionAsync(TestApp app, TestIdTokenSigner signer)
    {
        var idToken = signer.Mint("apple", "import-sub-" + Guid.NewGuid().ToString("N"), "import@example.com");
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

    private static async Task<HttpResponseMessage> ParseAsync(HttpClient client, string? format, byte[] fileBytes, string fileName, Guid deviceId, string? bearer = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/import/parse");
        request.Headers.TryAddWithoutValidation("X-Device-Id", deviceId.ToString());
        if (bearer is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        }

        request.Content = BuildMultipart(format, fileBytes, fileName);
        return await client.SendAsync(request);
    }

    private static HttpContent BuildMultipart(string? format, byte[] fileBytes, string fileName)
    {
        var content = new MultipartFormDataContent();
        if (format is not null)
        {
            content.Add(new StringContent(format), "format");
        }

        content.Add(new ByteArrayContent(fileBytes), "file", fileName);
        return content;
    }

    private static async Task<HttpResponseMessage> GetImportAsync(HttpClient client, Guid importId)
        => await client.GetAsync($"/v1/import/{importId}");

    private static async Task<HttpResponseMessage> DeleteImportAsync(HttpClient client, Guid importId)
        => await client.DeleteAsync($"/v1/import/{importId}");

    private static JsonElement ParseBody(string json) => JsonDocument.Parse(json).RootElement.Clone();

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

        public IServiceProvider Services => _factory.Services;

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
