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
using Tankbook.Api.Cases;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;
using Tankbook.Api.Tests.Auth;
using Tankbook.Api.Tests.Blobs;

namespace Tankbook.Api.Tests.Cases;

/// <summary>
/// L2 tests for POST /v1/cases (docs/API.md "Debug cases", hard rule 9's
/// debug-cases amendment) against real Postgres; IBlobStorage is a recording
/// double so the stored parts are assertable without S3.
/// </summary>
public class CaseEndpointTests : IClassFixture<PostgresFixture>
{
    private const string LogMarker = "event=capture.classify display=false rows=0 stationName=<redacted>";
    private const string PhotoMarker = "JPEG-BYTES-Zvezda-Lubricants-77";
    private readonly PostgresFixture _fixture;

    public CaseEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task Submit_SignedOut_StoresEveryPartUnderTheDevice_AndReturnsAPasteableId()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();

        using var response = await SubmitAsync(app.Client, deviceId, StandardParts());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        var caseId = body.GetProperty("caseId").GetString()!;
        Assert.Matches("^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$", caseId);
        var expiresText = body.GetProperty("expiresAt").GetString()!;
        Assert.Matches(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|\+00:00)$", expiresText);
        var expiresAt = body.GetProperty("expiresAt").GetDateTimeOffset();
        Assert.InRange(expiresAt - DateTimeOffset.UtcNow, TimeSpan.FromDays(29.9), TimeSpan.FromDays(30.1));

        Assert.Equal(1, await app.CountAsync("debug_cases", "id = @p AND device_id = @d AND account_id IS NULL",
                                             new { p = caseId, d = deviceId }));
        Assert.Equal(0, await app.CountAsync("accounts"));
        foreach (var (name, _, bytes) in StandardParts())
        {
            var key = CaseKeys.PartKey(deviceId, caseId, name);
            Assert.True(storage.ByteObjects.TryGetValue(key, out var stored), $"{name} was not stored");
            Assert.Equal(bytes, stored);
        }
    }

    [SkippableFact]
    public async Task Submit_WithoutADeviceIdentity_Is400_AndStoresNothing()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/cases") { Content = Multipart(StandardParts()) };
        using var response = await app.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(0, await app.CountAsync("debug_cases"));
        Assert.Empty(storage.ByteObjects);
    }

    [SkippableTheory]
    [InlineData("script.sh", "application/x-sh", HttpStatusCode.UnsupportedMediaType)]
    [InlineData("Bad Name", "text/plain", HttpStatusCode.BadRequest)]
    [InlineData("../escape", "text/plain", HttpStatusCode.BadRequest)]
    public async Task Submit_RefusesAnInvalidPart_AndStoresNothing(string name, string contentType, HttpStatusCode expected)
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var parts = StandardParts().Append((name, contentType, Encoding.UTF8.GetBytes("x"))).ToList();

        using var response = await SubmitAsync(app.Client, Guid.NewGuid(), parts);
        Assert.Equal(expected, response.StatusCode);
        Assert.Equal(0, await app.CountAsync("debug_cases"));
        Assert.Empty(storage.ByteObjects);
    }

    [SkippableFact]
    public async Task Submit_TooManyParts_Is413()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var parts = Enumerable.Range(0, CaseOptions.MaxParts + 1)
            .Select(i => ($"part-{i}.txt", "text/plain", Encoding.UTF8.GetBytes("x"))).ToList();

        using var response = await SubmitAsync(app.Client, Guid.NewGuid(), parts);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        Assert.Equal(0, await app.CountAsync("debug_cases"));
    }

    [SkippableFact]
    public async Task Purge_DropsACasePast30Days_AndKeepsOneInsideTheWindow()
    {
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage);
        var deviceId = Guid.NewGuid();
        var oldId = await SubmitIdAsync(app, deviceId);
        var recentId = await SubmitIdAsync(app, deviceId);
        await app.Db.ExecuteAsync("UPDATE debug_cases SET created_at = now() - interval '31 days' WHERE id = @p", new { p = oldId });
        await app.Db.ExecuteAsync("UPDATE debug_cases SET created_at = now() - interval '29 days' WHERE id = @p", new { p = recentId });

        using var scope = app.Services.CreateScope();
        var purged = await scope.ServiceProvider.GetRequiredService<CasePurgeService>().PurgeDueCasesAsync(CancellationToken.None);

        Assert.Equal(1, purged);
        Assert.Equal(1, await app.CountAsync("debug_cases", "id = @p", new { p = recentId }));
        Assert.True(storage.ByteObjects.ContainsKey(CaseKeys.PartKey(deviceId, recentId, "log.txt")));
        Assert.Equal(0, await app.CountAsync("debug_cases", "id = @p", new { p = oldId }));
        Assert.False(storage.ByteObjects.ContainsKey(CaseKeys.PartKey(deviceId, oldId, "log.txt")));
        Assert.False(storage.ByteObjects.ContainsKey(CaseKeys.PartKey(deviceId, oldId, "scan-1-photo.jpg")));
    }

    [SkippableFact]
    public async Task PurgeTimer_IsNotRegisteredInTheTestHost()
    {
        await using var app = await StartAsync(new RecordingBlobStorage());
        Assert.DoesNotContain(app.Services.GetServices<IHostedService>(), h => h is CasePurgeHostedService);
    }

    [SkippableFact]
    public async Task AccountPurge_DeletesTheCasesTheAccountSent()
    {
        var signer = new TestIdTokenSigner();
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage, accountDeletionGraceDays: 1, signer: signer);
        var (token, accountId) = await CreateSessionAsync(app, signer);

        using var response = await SubmitAsync(app.Client, Guid.NewGuid(), StandardParts(), token);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var caseId = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.GetProperty("caseId").GetString()!;
        Assert.Equal(1, await app.CountAsync("debug_cases", "id = @p AND account_id = @a", new { p = caseId, a = accountId }));
        Assert.True(storage.ByteObjects.ContainsKey(CaseKeys.PartKey(accountId, caseId, "log.txt")));

        await app.Db.ExecuteAsync("UPDATE accounts SET deleted_at = now() - interval '2 days' WHERE id = @p", new { p = accountId });
        using var scope = app.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AccountPurgeService>().PurgeDueAccountsAsync(CancellationToken.None);

        Assert.Equal(0, await app.CountAsync("debug_cases", "id = @p", new { p = caseId }));
        Assert.False(storage.ByteObjects.ContainsKey(CaseKeys.PartKey(accountId, caseId, "log.txt")));
    }

    [SkippableFact]
    public async Task Submit_LogsCarryShapeOnly_NeverAPartsNameOrContent()
    {
        var writer = new InMemoryLogWriter(new List<string>());
        var storage = new RecordingBlobStorage();
        await using var app = await StartAsync(storage, writer);

        using var response = await SubmitAsync(app.Client, Guid.NewGuid(), StandardParts());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        Assert.Contains(writer.Lines, l => l.Contains("case.accepted", StringComparison.Ordinal));
        var all = string.Join('\n', writer.Lines).WithoutMachineFields();
        Assert.DoesNotContain("Zvezda", all, StringComparison.Ordinal);
        Assert.DoesNotContain("capture.classify", all, StringComparison.Ordinal);
        Assert.DoesNotContain("scan-1-photo", all, StringComparison.Ordinal);
    }

    private static List<(string Name, string ContentType, byte[] Bytes)> StandardParts() =>
    [
        ("manifest.json", "application/json", Encoding.UTF8.GetBytes("{\"kind\":\"diagnostics\",\"scans\":1}")),
        ("log.txt", "text/plain", Encoding.UTF8.GetBytes(LogMarker)),
        ("scan-1-photo.jpg", "image/jpeg", Encoding.UTF8.GetBytes(PhotoMarker)),
        ("scan-1-trace.json", "application/json", Encoding.UTF8.GetBytes("{\"attempts\":[]}")),
    ];

    private static MultipartFormDataContent Multipart(IEnumerable<(string Name, string ContentType, byte[] Bytes)> parts)
    {
        var content = new MultipartFormDataContent();
        foreach (var (name, contentType, bytes) in parts)
        {
            var part = new ByteArrayContent(bytes);
            part.Headers.ContentType = MediaTypeHeaderValue.Parse(contentType);
            content.Add(part, name, name);
        }

        return content;
    }

    private static async Task<HttpResponseMessage> SubmitAsync(HttpClient client, Guid deviceId,
        IEnumerable<(string Name, string ContentType, byte[] Bytes)> parts, string? bearer = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/cases") { Content = Multipart(parts) };
        request.Headers.TryAddWithoutValidation("X-Device-Id", deviceId.ToString());
        if (bearer is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        }

        return await client.SendAsync(request);
    }

    private static async Task<string> SubmitIdAsync(TestApp app, Guid deviceId)
    {
        using var response = await SubmitAsync(app.Client, deviceId, StandardParts());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.GetProperty("caseId").GetString()!;
    }

    private static async Task<(string AccessToken, Guid AccountId)> CreateSessionAsync(TestApp app, TestIdTokenSigner signer)
    {
        var idToken = signer.Mint("apple", "case-sub-" + Guid.NewGuid().ToString("N"), "case@example.com");
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

    private async Task<TestApp> StartAsync(RecordingBlobStorage storage, InMemoryLogWriter? writer = null,
                                           int? accountDeletionGraceDays = null, TestIdTokenSigner? signer = null)
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
                b.UseSetting("Logging:LogLevel:Default", "Debug");
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

    private sealed class TestApp : IAsyncDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;

        public TestApp(WebApplicationFactory<Program> factory, HttpClient client, NpgsqlConnection db)
        {
            _factory = factory;
            Client = client;
            Db = db;
        }

        public HttpClient Client { get; }

        public NpgsqlConnection Db { get; }

        public IServiceProvider Services => _factory.Services;

        public Task<int> CountAsync(string table, string? where = null, object? param = null)
            => Db.QuerySingleAsync<int>(
                $"SELECT count(*) FROM {table}" + (where is null ? "" : " WHERE " + where),
                param ?? new { });

        public async ValueTask DisposeAsync()
        {
            Client.Dispose();
            await Db.DisposeAsync();
            _factory.Dispose();
        }
    }
}
