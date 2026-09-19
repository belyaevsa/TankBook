using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Dapper;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Npgsql;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Reference;

/// <summary>
/// L2 tests for GET /v1/reference/station-brands (docs/API.md, RV.115) against
/// real Postgres: the seeded pack of migration 025 serves as a full pack,
/// public and ETag'd; a since_version at the held version is an honest empty
/// delta; a later correction serves as a delta above the held version; and the
/// pack carries what the device's matcher needs - aliases in several scripts
/// and a country per brand.
/// </summary>
public class StationBrandEndpointTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public StationBrandEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static StationBrandEndpointTests()
    {
        DapperTypeHandlers.Register();
    }

    /// <summary>ios/Sources/TankbookCore/Stations/StationBrands.seed.json -> packVersion.</summary>
    private const int BundledSeedPackVersion = 1;

    [SkippableFact]
    public async Task FullPack_IsPublic_Cacheable_AndCarriesAliasesAndCountries()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var factory = Factory(db.ConnectionString);
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/v1/reference/station-brands");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl!.Public);
        Assert.Equal(TimeSpan.FromMinutes(5), response.Headers.CacheControl.MaxAge);
        Assert.NotNull(response.Headers.ETag);

        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("full", body.GetProperty("kind").GetString());
        Assert.Equal(BundledSeedPackVersion, body.GetProperty("packVersion").GetInt32());
        var brands = body.GetProperty("brands").EnumerateArray().ToList();
        Assert.True(brands.Count >= 100, $"a brand vocabulary, not a sample: {brands.Count}");

        var gazprom = brands.Single(b => b.GetProperty("id").GetString() == "gazpromneft");
        Assert.Equal("RU", gazprom.GetProperty("country").GetString());
        var aliases = gazprom.GetProperty("aliases").EnumerateArray().Select(a => a.GetString()).ToList();
        Assert.Contains("Газпромнефть", aliases);
        Assert.Contains("G-Drive", aliases);
        Assert.All(brands, b => Assert.Equal(2, b.GetProperty("country").GetString()!.Length));
    }

    [SkippableFact]
    public async Task Etag_MatchingIfNoneMatchIs304()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var factory = Factory(db.ConnectionString);
        using var client = factory.CreateClient();

        using var first = await client.GetAsync("/v1/reference/station-brands");
        var etag = first.Headers.ETag!.Tag;
        using var conditional = new HttpRequestMessage(HttpMethod.Get, "/v1/reference/station-brands");
        conditional.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(etag, isWeak: false));
        using var second = await client.SendAsync(conditional);
        Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
    }

    [SkippableFact]
    public async Task SinceVersion_AtTheHeldVersionIsAnEmptyDelta_AndACorrectionServesAsADelta()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var factory = Factory(db.ConnectionString);
        using var client = factory.CreateClient();

        using var upToDate = await client.GetAsync($"/v1/reference/station-brands?since_version={BundledSeedPackVersion}");
        var upToDateBody = JsonDocument.Parse(await upToDate.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("delta", upToDateBody.GetProperty("kind").GetString());
        Assert.Equal(0, upToDateBody.GetProperty("brands").GetArrayLength());

        // An operator corrects one alias list - written straight to the
        // database, the only write surface there is.
        await db.ExecuteAsync(
            "UPDATE station_brands SET aliases = array_append(aliases, 'Газпромнефть-Восток'), pack_version = 2 WHERE id = 'gazpromneft'");
        await db.ExecuteAsync("UPDATE station_brand_pack_state SET pack_version = 2 WHERE singleton = 1");

        using var delta = await client.GetAsync($"/v1/reference/station-brands?since_version={BundledSeedPackVersion}");
        var deltaBody = JsonDocument.Parse(await delta.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("delta", deltaBody.GetProperty("kind").GetString());
        Assert.Equal(2, deltaBody.GetProperty("packVersion").GetInt32());
        var changed = Assert.Single(deltaBody.GetProperty("brands").EnumerateArray());
        Assert.Equal("gazpromneft", changed.GetProperty("id").GetString());
        Assert.Contains("Газпромнефть-Восток", changed.GetProperty("aliases").EnumerateArray().Select(a => a.GetString()));

        using var malformed = await client.GetAsync("/v1/reference/station-brands?since_version=abc");
        Assert.Equal(HttpStatusCode.BadRequest, malformed.StatusCode);
    }

    private async Task<NpgsqlConnection> OpenAndMigrateAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static WebApplicationFactory<Program> Factory(string connectionString)
        => new WebApplicationFactory<Program>().WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Testing");
            b.UseSetting("ConnectionStrings:Postgres", connectionString);
        });
}
