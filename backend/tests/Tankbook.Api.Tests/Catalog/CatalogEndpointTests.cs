using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Npgsql;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Catalog;

/// <summary>
/// L2 tests for GET /v1/catalog and POST /v1/catalog/publish (docs/API.md
/// "Vehicle catalog", docs/SYNC.md "Reference data") against real Postgres via
/// Testcontainers. The database, the endpoint wiring, the cache headers and the
/// ETag flow are all real - only the admin token and the delta threshold are
/// test-scaled via configuration.
/// </summary>
public class CatalogEndpointTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public CatalogEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static CatalogEndpointTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task Delta_ReturnsOnlyEntriesChangedSinceTheVersion_ByIdentity()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var a = new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m);
        var b = new CatalogTestData.Entry(Guid.NewGuid(), "Toyota", "Corolla", TankCapacityL: 50m);
        var c = new CatalogTestData.Entry(Guid.NewGuid(), "Renault", "Clio", TankCapacityL: 45m);

        await PublishAsync(client, CatalogTestData.Pack(1, a, b, c));
        await PublishAsync(client, CatalogTestData.Pack(2, b with { TankCapacityL = 52m }));
        await PublishAsync(client, CatalogTestData.Pack(3, c with { TankCapacityL = 44m }));

        // since=1: exactly B and C changed (B at v2, C at v3), never A, never
        // anything else. Asserted by identity AND by the correct version's value.
        var deltaFrom1 = await GetAsync(client, "/v1/catalog?since_version=1");
        Assert.Equal(HttpStatusCode.OK, deltaFrom1.StatusCode);
        var body1 = JsonDocument.Parse(await deltaFrom1.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(3, body1.GetProperty("packVersion").GetInt32());
        var entries1 = EntriesById(body1);
        Assert.Equal(new[] { b.Id, c.Id }.OrderBy(x => x).ToArray(),
            entries1.Keys.OrderBy(x => x).ToArray());
        Assert.Equal(52m, entries1[b.Id].GetProperty("tankCapacityL").GetDecimal());
        Assert.Equal(44m, entries1[c.Id].GetProperty("tankCapacityL").GetDecimal());

        // since=2: only C changed.
        var deltaFrom2 = await GetAsync(client, "/v1/catalog?since_version=2");
        var body2 = JsonDocument.Parse(await deltaFrom2.Content.ReadAsStringAsync()).RootElement;
        var entries2 = EntriesById(body2);
        Assert.Equal(new[] { c.Id }, entries2.Keys.ToArray());

        // since=0: everything since the beginning - all three.
        var deltaFrom0 = await GetAsync(client, "/v1/catalog?since_version=0");
        var body0 = JsonDocument.Parse(await deltaFrom0.Content.ReadAsStringAsync()).RootElement;
        var entries0 = EntriesById(body0);
        Assert.Equal(new[] { a.Id, b.Id, c.Id }.OrderBy(x => x).ToArray(),
            entries0.Keys.OrderBy(x => x).ToArray());

        // Full pack (no since_version): all three, B and C at their latest values.
        var full = await GetAsync(client, "/v1/catalog");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(3, fullBody.GetProperty("entries").GetArrayLength());
        var fullEntries = EntriesById(fullBody);
        Assert.Equal(52m, fullEntries[b.Id].GetProperty("tankCapacityL").GetDecimal());
        Assert.Equal(44m, fullEntries[c.Id].GetProperty("tankCapacityL").GetDecimal());
    }

    [SkippableFact]
    public async Task FullPack_ServedWhenTheDeltaExceedsTheThreshold_DeltaOtherwise()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        // MaxDeltaEntries = 2: a delta of ≤ 2 changed entries is served as a
        // delta; more than 2 and the client is "too far behind" - full pack.
        using var app = await StartAsync(db.ConnectionString, maxDeltaEntries: 2);
        using var client = app.Client;

        var e1 = new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m);
        var e2 = new CatalogTestData.Entry(Guid.NewGuid(), "Toyota", "Corolla", TankCapacityL: 50m);
        var e3 = new CatalogTestData.Entry(Guid.NewGuid(), "Renault", "Clio", TankCapacityL: 45m);
        var e4 = new CatalogTestData.Entry(Guid.NewGuid(), "Skoda", "Octavia", TankCapacityL: 60m);
        var e5 = new CatalogTestData.Entry(Guid.NewGuid(), "Kia", "Rio", TankCapacityL: 43m);

        await PublishAsync(client, CatalogTestData.Pack(1, e1, e2, e3, e4, e5));
        await PublishAsync(client, CatalogTestData.Pack(2, e1 with { TankCapacityL = 72m }));

        // Side one of the threshold: 1 changed entry ≤ 2, so a delta (only e1).
        var delta = await GetAsync(client, "/v1/catalog?since_version=1");
        var deltaBody = JsonDocument.Parse(await delta.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(2, deltaBody.GetProperty("packVersion").GetInt32());
        var deltaEntries = EntriesById(deltaBody);
        Assert.Equal(new[] { e1.Id }, deltaEntries.Keys.ToArray());

        // Side two: 4 changed entries > 2, so a full pack (all five).
        await PublishAsync(client, CatalogTestData.Pack(3, e2 with { TankCapacityL = 51m }, e3 with { TankCapacityL = 46m }, e4 with { TankCapacityL = 61m }));
        var full = await GetAsync(client, "/v1/catalog?since_version=1");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(3, fullBody.GetProperty("packVersion").GetInt32());
        Assert.Equal(5, fullBody.GetProperty("entries").GetArrayLength());
        Assert.Equal(5, EntriesById(fullBody).Count);
    }

    [SkippableFact]
    public async Task Etag_MatchingIfNoneMatchIs304_NonMatchingIs200WithBody()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        await PublishAsync(client, CatalogTestData.Pack(1,
            new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m)));

        var first = await GetAsync(client, "/v1/catalog");
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var etag = first.Headers.ETag!.Tag;

        // Matching If-None-Match: 304, no body, ETag echoed.
        using (var conditional = new HttpRequestMessage(HttpMethod.Get, "/v1/catalog"))
        {
            conditional.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(etag, isWeak: false));
            var second = await client.SendAsync(conditional);
            Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
            Assert.Equal(etag, second.Headers.ETag?.Tag);
            Assert.Equal(string.Empty, await second.Content.ReadAsStringAsync());
        }

        // The "*" form is a match for any current representation.
        using (var star = new HttpRequestMessage(HttpMethod.Get, "/v1/catalog"))
        {
            star.Headers.IfNoneMatch.Add(EntityTagHeaderValue.Any);
            var starResponse = await client.SendAsync(star);
            Assert.Equal(HttpStatusCode.NotModified, starResponse.StatusCode);
        }

        // Non-matching If-None-Match: 200 with the body.
        using var nonMatching = new HttpRequestMessage(HttpMethod.Get, "/v1/catalog");
        nonMatching.Headers.TryAddWithoutValidation("If-None-Match", "\"1:deadbeef\"");
        var third = await client.SendAsync(nonMatching);
        Assert.Equal(HttpStatusCode.OK, third.StatusCode);
        Assert.Equal(1, JsonDocument.Parse(await third.Content.ReadAsStringAsync()).RootElement
            .GetProperty("entries").GetArrayLength());
    }

    [SkippableFact]
    public async Task SchemaRejectedPack_IsRefusedAtPublish_AndThePreviousPackStillServes()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var volvo = new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m);
        await PublishAsync(client, CatalogTestData.Pack(1, volvo));

        // A pack missing the required fuelKinds on its entry fails the schema.
        var invalid = CatalogTestData.Pack(2,
            new CatalogTestData.Entry(Guid.NewGuid(), "Toyota", "Corolla", FuelKinds: []));
        using var refused = await PostPackAsync(client, invalid);
        Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);

        // The refusal is at publish time AND the endpoint still serves the
        // previously published pack untouched - asserting the publish call alone
        // would prove nothing about what is served.
        var after = await GetAsync(client, "/v1/catalog");
        var body = JsonDocument.Parse(await after.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(1, body.GetProperty("packVersion").GetInt32());
        var entries = EntriesById(body);
        Assert.Single(entries);
        Assert.Equal(volvo.Id, entries.Keys.Single());
        Assert.Equal(71m, entries.Values.Single().GetProperty("tankCapacityL").GetDecimal());
    }

    [SkippableFact]
    public async Task Publish_PackVersionNotGreaterThanCurrent_IsRefused_EqualAndLower()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var volvo = new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m);
        await PublishAsync(client, CatalogTestData.Pack(1, volvo));
        await PublishAsync(client, CatalogTestData.Pack(2, volvo with { TankCapacityL = 72m }));

        // The lower version (1 < current 2) is refused...
        using var lower = await PostPackAsync(client, CatalogTestData.Pack(1, volvo with { TankCapacityL = 73m }));
        Assert.Equal(HttpStatusCode.Conflict, lower.StatusCode);

        // ...and so is the equal version (2 == current 2). The >= vs > slip is
        // exactly the likely bug: if the check were >= instead of >, the equal
        // case would slip through and re-publish version 2 as a "rollback".
        using var equal = await PostPackAsync(client, CatalogTestData.Pack(2, volvo with { TankCapacityL = 73m }));
        Assert.Equal(HttpStatusCode.Conflict, equal.StatusCode);

        // Both refusals left the stored pack unchanged: still one row, version 2.
        var stored = await db.QueryAsync<(Guid Id, int PackVersion, decimal Capacity)>(
            "SELECT id, pack_version, tank_capacity_l FROM vehicle_catalog");
        var row = Assert.Single(stored);
        Assert.Equal(2, row.PackVersion);
        Assert.Equal(72m, row.Capacity);

        var after = await GetAsync(client, "/v1/catalog");
        var body = JsonDocument.Parse(await after.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(2, body.GetProperty("packVersion").GetInt32());
        Assert.Equal(72m, EntriesById(body).Values.Single().GetProperty("tankCapacityL").GetDecimal());
    }

    [SkippableFact]
    public async Task PublicEndpoint_ReachableWithoutBearer_CurationPathIsGated()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        // GET /catalog carries no Authorization header at all - it must serve.
        using var publicRequest = new HttpRequestMessage(HttpMethod.Get, "/v1/catalog");
        Assert.Null(publicRequest.Headers.Authorization);
        var publicResponse = await client.SendAsync(publicRequest);
        Assert.Equal(HttpStatusCode.OK, publicResponse.StatusCode);

        var pack = CatalogTestData.Pack(1,
            new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m));

        // The curation path is NOT public: no token, then a wrong token.
        using var noToken = new HttpRequestMessage(HttpMethod.Post, "/v1/catalog/publish")
        {
            Content = new StringContent(pack, Encoding.UTF8, "application/json"),
        };
        var noTokenResponse = await client.SendAsync(noToken);
        Assert.Equal(HttpStatusCode.Unauthorized, noTokenResponse.StatusCode);

        using var wrongToken = new HttpRequestMessage(HttpMethod.Post, "/v1/catalog/publish")
        {
            Content = new StringContent(pack, Encoding.UTF8, "application/json"),
        };
        wrongToken.Headers.Add("X-Admin-Token", "not-the-token");
        var wrongTokenResponse = await client.SendAsync(wrongToken);
        Assert.Equal(HttpStatusCode.Unauthorized, wrongTokenResponse.StatusCode);

        // The right token publishes.
        using var rightToken = new HttpRequestMessage(HttpMethod.Post, "/v1/catalog/publish")
        {
            Content = new StringContent(pack, Encoding.UTF8, "application/json"),
        };
        rightToken.Headers.Add("X-Admin-Token", CatalogTestData.AdminToken);
        var rightTokenResponse = await client.SendAsync(rightToken);
        Assert.Equal(HttpStatusCode.OK, rightTokenResponse.StatusCode);
    }

    [SkippableFact]
    public async Task Publish_WithNoAdminTokenConfigured_IsDisabled()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        // No Catalog:AdminToken in configuration: curation answers 503, never 401.
        using var app = await StartAsync(db.ConnectionString, adminToken: null);
        using var client = app.Client;

        var response = await client.PostAsync("/v1/catalog/publish",
            new StringContent(CatalogTestData.Pack(1), Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [SkippableFact]
    public async Task SinceVersion_AtOrAboveTheCurrentVersion_IsAnHonestEmptyDelta()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        await PublishAsync(client, CatalogTestData.Pack(3,
            new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m)));

        // since == current: an empty delta carrying the current packVersion -
        // never a fabricated entry, never a full pack pretending to be a delta.
        var atCurrent = await GetAsync(client, "/v1/catalog?since_version=3");
        Assert.Equal(HttpStatusCode.OK, atCurrent.StatusCode);
        var body = JsonDocument.Parse(await atCurrent.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(3, body.GetProperty("packVersion").GetInt32());
        Assert.Empty(body.GetProperty("entries").EnumerateArray());

        // since > current is the same honest empty answer.
        var aboveCurrent = await GetAsync(client, "/v1/catalog?since_version=9");
        var aboveBody = JsonDocument.Parse(await aboveCurrent.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(3, aboveBody.GetProperty("packVersion").GetInt32());
        Assert.Empty(aboveBody.GetProperty("entries").EnumerateArray());

        // And the empty-delta body is ETag'd too: a matching If-None-Match is 304.
        using (var conditional = new HttpRequestMessage(HttpMethod.Get, "/v1/catalog?since_version=3"))
        {
            conditional.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(atCurrent.Headers.ETag!.Tag, isWeak: false));
            var second = await client.SendAsync(conditional);
            Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
        }
    }

    [SkippableFact]
    public async Task MissingSinceVersion_ServesAFullPack_ByDocumentedDefault()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        await PublishAsync(client, CatalogTestData.Pack(1,
            new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m)));

        var response = await GetAsync(client, "/v1/catalog");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(1, body.GetProperty("packVersion").GetInt32());
        Assert.Equal(1, body.GetProperty("entries").GetArrayLength());
    }

    [SkippableFact]
    public async Task MalformedSinceVersion_IsA400ProblemJson()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var notAnInt = await GetAsync(client, "/v1/catalog?since_version=abc");
        Assert.Equal(HttpStatusCode.BadRequest, notAnInt.StatusCode);

        var negative = await GetAsync(client, "/v1/catalog?since_version=-1");
        Assert.Equal(HttpStatusCode.BadRequest, negative.StatusCode);
    }

    [SkippableFact]
    public async Task EmptyCatalog_ServesAnHonestEmptyFullPack()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var response = await GetAsync(client, "/v1/catalog");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(0, body.GetProperty("packVersion").GetInt32());
        Assert.Empty(body.GetProperty("entries").EnumerateArray());
    }

    [SkippableFact]
    public async Task Publish_SuccessReportsTheVersionAndCount()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        using var response = await PostPackAsync(client, CatalogTestData.Pack(4,
            new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", Years: [2018, 2025], FuelKinds: ["petrol95", "diesel"], TankCapacityL: 71m),
            new CatalogTestData.Entry(Guid.NewGuid(), "Tesla", "Model 3", Powertrain: "ev", FuelKinds: ["electricity"], BatteryCapacityKwh: 60m)));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(4, body.GetProperty("packVersion").GetInt32());
        Assert.Equal(2, body.GetProperty("entriesPublished").GetInt32());

        // The full round trip: years and the offer set survive exactly.
        var full = await GetAsync(client, "/v1/catalog");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(4, fullBody.GetProperty("packVersion").GetInt32());
        var entries = EntriesById(fullBody);
        var volvo = entries.Values.First(e => e.GetProperty("make").GetString() == "Volvo");
        Assert.Equal(new[] { 2018, 2025 }, volvo.GetProperty("years").EnumerateArray().Select(y => y.GetInt32()).ToArray());
        Assert.Equal(new[] { "petrol95", "diesel" }, volvo.GetProperty("fuelKinds").EnumerateArray().Select(f => f.GetString()).ToArray());
        Assert.Equal(71m, volvo.GetProperty("tankCapacityL").GetDecimal());
    }

    private async Task<NpgsqlConnection> OpenAndMigrateAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static async Task<HttpResponseMessage> GetAsync(HttpClient client, string url)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> PostPackAsync(HttpClient client, string packJson)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/catalog/publish")
        {
            Content = new StringContent(packJson, Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("X-Admin-Token", CatalogTestData.AdminToken);
        return await client.SendAsync(request);
    }

    private static async Task PublishAsync(HttpClient client, string packJson)
    {
        using var response = await PostPackAsync(client, packJson);
        Assert.True(response.IsSuccessStatusCode, $"publish {response.StatusCode}: {await response.Content.ReadAsStringAsync()}");
    }

    private static Dictionary<Guid, JsonElement> EntriesById(JsonElement body)
    {
        var result = new Dictionary<Guid, JsonElement>();
        foreach (var entry in body.GetProperty("entries").EnumerateArray())
        {
            result[Guid.Parse(entry.GetProperty("id").GetString()!)] = entry.Clone();
        }

        return result;
    }

    private static async Task<CatalogTestApp> StartAsync(string connectionString, string? adminToken = CatalogTestData.AdminToken, int? maxDeltaEntries = null)
    {
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:Postgres", connectionString);
                if (adminToken is not null)
                {
                    b.UseSetting("Catalog:AdminToken", adminToken);
                }

                if (maxDeltaEntries is not null)
                {
                    b.UseSetting("Catalog:MaxDeltaEntries", maxDeltaEntries.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
                }
            });

        return new CatalogTestApp(factory, factory.CreateClient());
    }

    private sealed class CatalogTestApp : IDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;

        public CatalogTestApp(WebApplicationFactory<Program> factory, HttpClient client)
        {
            _factory = factory;
            Client = client;
        }

        public HttpClient Client { get; }

        public void Dispose()
        {
            Client.Dispose();
            _factory.Dispose();
        }
    }
}
