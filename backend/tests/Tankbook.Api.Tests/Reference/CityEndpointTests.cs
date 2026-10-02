using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Tankbook.Api.Tests.Reference;

/// <summary>
/// L2 tests for GET /v1/reference/cities (docs/API.md): the committed dictionary
/// file is served public, cacheable and ETag'd, revalidates to 304, and is the
/// same file the app bundles.
/// </summary>
public class CityEndpointTests
{
    private static WebApplicationFactory<Program> Factory()
        => new WebApplicationFactory<Program>().WithWebHostBuilder(b => b.UseEnvironment("Testing"));

    [Fact]
    public async Task TheDictionaryIsPublic_Cacheable_AndTheBundledFile()
    {
        using var factory = Factory();
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/v1/reference/cities");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl!.Public);
        Assert.NotNull(response.Headers.ETag);

        var body = await response.Content.ReadAsStringAsync();
        var bundled = await File.ReadAllTextAsync(Path.Combine(DocPaths.RepositoryRoot, "ios", "Sources", "TankbookCore", "Places", "Cities.seed.json"));
        Assert.Equal(bundled, body);
        var root = JsonDocument.Parse(body).RootElement;
        Assert.True(root.GetProperty("version").GetInt32() > 0);
        Assert.Contains(root.GetProperty("cities").EnumerateArray(),
            c => c.GetProperty("en").GetString() == "Tallinn" && c.GetProperty("c").GetString() == "EE");
    }

    [Fact]
    public async Task ARevalidationWithTheEtagIsNotModified()
    {
        using var factory = Factory();
        using var client = factory.CreateClient();

        using var first = await client.GetAsync("/v1/reference/cities");
        using var conditional = new HttpRequestMessage(HttpMethod.Get, "/v1/reference/cities");
        conditional.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(first.Headers.ETag!.Tag, isWeak: false));
        using var second = await client.SendAsync(conditional);
        Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
    }
}
