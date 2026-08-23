using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// The GET /v1/config wire shape (docs/API.md reference data). One thin host
/// test per the standing rule (docs/TESTING.md "mock the boundary"): the read
/// service behind the endpoint is replaced with a fake, so this exercises
/// routing, the ETag/304 flow and auth-independence - not the database. The
/// database selection logic is covered separately against real Postgres.
/// </summary>
public class ConfigEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private const string FakeDocument =
        "{\"version\":1,\"issuedAt\":\"2026-08-01T00:00:00Z\",\"notAfter\":\"2026-11-01T00:00:00Z\"," +
        "\"tier2OnDeviceLLM\":true,\"tier3CloudFallback\":true," +
        "\"llmQuota\":{\"onDeviceLLM\":200,\"cloudFallback\":50},\"ocrConfidenceThreshold\":0.75," +
        "\"minSchemaVersion\":1,\"referencePacks\":{\"rates\":1,\"catalog\":1},\"rolloutSalt\":\"test\"}";
    private const string FakeSignature = "U2lnbmF0dXJlT2Z0aGVGYWtlRG9jdW1lbnQ=";

    private readonly WebApplicationFactory<Program> _factory;

    public ConfigEndpointTests(WebApplicationFactory<Program> factory)
    {
        // "Testing" loads only appsettings.json (empty Config:SigningKey, empty
        // ConnectionStrings:Postgres), so the migration host has nothing to do
        // and the endpoint behaviour below is fully deterministic.
        _factory = factory.WithWebHostBuilder(b => b.UseEnvironment("Testing"));
    }

    [Fact]
    public async Task GetConfig_Returns200WithDocumentSignatureVersionAndStrongEtag()
    {
        var client = ClientWithFakeRead();

        var response = await client.GetAsync("/v1/config");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        // Kestrel may reorder cache-control directives; assert the pair.
        Assert.Contains("max-age=300", response.Headers.CacheControl?.ToString());
        Assert.Contains("must-revalidate", response.Headers.CacheControl?.ToString());
        Assert.False(string.IsNullOrWhiteSpace(response.Headers.ETag?.Tag));
        Assert.True(response.Headers.ETag!.IsWeak == false);

        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(1, body.GetProperty("version").GetInt32());
        Assert.Equal(FakeSignature, body.GetProperty("signature").GetString());
        Assert.Equal(1, body.GetProperty("document").GetProperty("version").GetInt32());
        Assert.True(body.GetProperty("document").GetProperty("tier3CloudFallback").GetBoolean());
    }

    [Fact]
    public async Task GetConfig_WithMatchingIfNoneMatch_Returns304WithEmptyBody()
    {
        var client = ClientWithFakeRead();

        var first = await client.GetAsync("/v1/config");
        var etag = first.Headers.ETag!.Tag;

        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        request.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(etag, isWeak: false));
        var second = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
        Assert.Equal(etag, second.Headers.ETag?.Tag);
        var body = await second.Content.ReadAsStringAsync();
        Assert.Equal(string.Empty, body);
    }

    [Fact]
    public async Task GetConfig_StarIfNoneMatch_Returns304()
    {
        var client = ClientWithFakeRead();

        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        request.Headers.IfNoneMatch.Add(EntityTagHeaderValue.Any);
        var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NotModified, response.StatusCode);
        Assert.Equal(string.Empty, await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task GetConfig_WorksWithoutAnAuthorizationHeader()
    {
        var client = ClientWithFakeRead();

        // The request deliberately carries no Authorization header at all.
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        Assert.Null(request.Headers.Authorization);
        var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task GetConfig_UnchangedEtagAcrossCalls_IsStable()
    {
        var client = ClientWithFakeRead();

        var a = await client.GetAsync("/v1/config");
        var b = await client.GetAsync("/v1/config");

        Assert.Equal(a.Headers.ETag!.Tag, b.Headers.ETag!.Tag);
    }

    [Fact]
    public async Task GetPublicKey_WithConfiguredSigningKey_ReturnsKeyIdAndPublicKey()
    {
        var client = _factory
            .WithWebHostBuilder(b => b.ConfigureAppConfiguration((_, cfg) => cfg.AddInMemoryCollection(
                new Dictionary<string, string?> { ["Config:SigningKey"] = ConfigTestData.SeedBase64 })))
            .CreateClient();

        var response = await client.GetAsync("/v1/config/public-key");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        var publicKey = Convert.FromBase64String(body.GetProperty("publicKey").GetString()!);
        Assert.Equal(32, publicKey.Length);
        Assert.Equal(16, body.GetProperty("keyId").GetString()!.Length);
        Assert.Equal(ConfigTestData.Signer.PublicKeyBase64, body.GetProperty("publicKey").GetString());
    }

    [Fact]
    public async Task GetPublicKey_WithoutConfiguredSigningKey_Returns503()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/v1/config/public-key");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task GetConfig_InvalidEtagOnBody_IsNotServedAs304()
    {
        var client = ClientWithFakeRead();

        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        request.Headers.TryAddWithoutValidation("If-None-Match", "\"1:deadbeef\"");
        var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private HttpClient ClientWithFakeRead()
        => _factory
            .WithWebHostBuilder(b => b.ConfigureServices(services =>
            {
                services.Replace(ServiceDescriptor.Singleton<IConfigReadService>(new FakeReadService()));
            }))
            .CreateClient();

    private sealed class FakeReadService : IConfigReadService
    {
        public Task<ConfigServeResult?> GetForServingAsync(CancellationToken cancellationToken)
            => Task.FromResult<ConfigServeResult?>(new ConfigServeResult(1, FakeDocument, FakeSignature));
    }
}
