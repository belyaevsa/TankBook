using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Dapper;
using Npgsql;
using Microsoft.Extensions.DependencyInjection;
using Tankbook.Api.Catalog;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Catalog;

/// <summary>
/// L2 tests for GET /v1/catalog (docs/API.md
/// "Vehicle catalog", docs/SYNC.md "Reference data") against real Postgres via
/// Testcontainers. The database, the endpoint wiring, the cache headers and the
/// ETag flow are all real - only the delta threshold is test-scaled via
/// configuration.
///
/// Packs are seeded through <see cref="CatalogPublishService"/>, which is how
/// they are written now that the publish endpoint is gone (2026-09-01): straight
/// into the database. The schema and monotonic-version guarantees are asserted
/// against that service, so they still hold for the path that actually runs.
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

        await SeedAsync(app, CatalogTestData.Pack(1, a, b, c));
        await SeedAsync(app, CatalogTestData.Pack(2, b with { TankCapacityL = 52m }));
        await SeedAsync(app, CatalogTestData.Pack(3, c with { TankCapacityL = 44m }));

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

        await SeedAsync(app, CatalogTestData.Pack(1, e1, e2, e3, e4, e5));
        await SeedAsync(app, CatalogTestData.Pack(2, e1 with { TankCapacityL = 72m }));

        // Side one of the threshold: 1 changed entry ≤ 2, so a delta (only e1).
        var delta = await GetAsync(client, "/v1/catalog?since_version=1");
        var deltaBody = JsonDocument.Parse(await delta.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(2, deltaBody.GetProperty("packVersion").GetInt32());
        var deltaEntries = EntriesById(deltaBody);
        Assert.Equal(new[] { e1.Id }, deltaEntries.Keys.ToArray());

        // Side two: 4 changed entries > 2, so a full pack (all five).
        await SeedAsync(app, CatalogTestData.Pack(3, e2 with { TankCapacityL = 51m }, e3 with { TankCapacityL = 46m }, e4 with { TankCapacityL = 61m }));
        var full = await GetAsync(client, "/v1/catalog?since_version=1");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(3, fullBody.GetProperty("packVersion").GetInt32());
        Assert.Equal(5, fullBody.GetProperty("entries").GetArrayLength());
        Assert.Equal(5, EntriesById(fullBody).Count);
    }

    [SkippableFact]
    public async Task EveryResponseNamesItsKind_FullAndDeltaFromTheSameEndpoint()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        // Even an empty catalog's full pack (missing since_version) names its kind.
        var empty = await GetAsync(client, "/v1/catalog");
        var emptyBody = JsonDocument.Parse(await empty.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("full", emptyBody.GetProperty("kind").GetString());

        var volvo = new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m);
        var toyota = new CatalogTestData.Entry(Guid.NewGuid(), "Toyota", "Corolla", TankCapacityL: 50m);
        var clio = new CatalogTestData.Entry(Guid.NewGuid(), "Renault", "Clio", TankCapacityL: 45m);
        await SeedAsync(app, CatalogTestData.Pack(1, volvo, toyota));
        await SeedAsync(app, CatalogTestData.Pack(2, clio));

        // Full pack (no since_version): marked "full". A test of only this side
        // would pass an implementation that hard-codes the marker - the delta
        // half below is what pins it.
        var full = await GetAsync(client, "/v1/catalog");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(2, fullBody.GetProperty("packVersion").GetInt32());
        Assert.Equal(3, fullBody.GetProperty("entries").GetArrayLength());
        Assert.Equal("full", fullBody.GetProperty("kind").GetString());

        // Delta (since_version=1): marked "delta", entries are only what changed.
        var delta = await GetAsync(client, "/v1/catalog?since_version=1");
        var deltaBody = JsonDocument.Parse(await delta.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("delta", deltaBody.GetProperty("kind").GetString());
        Assert.Equal(2, deltaBody.GetProperty("packVersion").GetInt32());
        Assert.Equal(new[] { clio.Id }, EntriesById(deltaBody).Keys.ToArray());

        // An honest empty delta (since == current) is still marked "delta" -
        // the marker is never inferred from a non-empty entries array.
        var emptyDelta = await GetAsync(client, "/v1/catalog?since_version=2");
        var emptyDeltaBody = JsonDocument.Parse(await emptyDelta.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("delta", emptyDeltaBody.GetProperty("kind").GetString());
        Assert.Equal(2, emptyDeltaBody.GetProperty("packVersion").GetInt32());
        Assert.Empty(emptyDeltaBody.GetProperty("entries").EnumerateArray());
    }

    [SkippableFact]
    public async Task PublishWithRemovedIds_WithdrawsTheEntry_AndTheFullPackLacksIt()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var volvo = new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", TankCapacityL: 71m);
        var toyota = new CatalogTestData.Entry(Guid.NewGuid(), "Toyota", "Corolla", TankCapacityL: 50m);
        await SeedAsync(app, CatalogTestData.Pack(1, volvo, toyota));

        // A pack that withdraws the Volvo (removedIds) and corrects the Toyota
        // in the same publish: removal IS expressible on the wire.
        var correctedToyota = toyota with { TankCapacityL = 51m };
        var withdrawal = await PublishAsync(app, CatalogTestData.Pack(2, [correctedToyota], [volvo.Id]));
        Assert.True(withdrawal.IsSuccess);

        // The subsequent full pack lacks the withdrawn entry entirely - the row
        // is physically gone, not merely unpresented for one client.
        var full = await GetAsync(client, "/v1/catalog");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal("full", fullBody.GetProperty("kind").GetString());
        Assert.Equal(2, fullBody.GetProperty("packVersion").GetInt32());
        var entries = EntriesById(fullBody);
        Assert.Equal(new[] { toyota.Id }, entries.Keys.OrderBy(x => x).ToArray());
        Assert.Equal(51m, entries[toyota.Id].GetProperty("tankCapacityL").GetDecimal());

        // And the withdrawn row is gone from the database, not hidden.
        var ids = (await db.QueryAsync<Guid>("SELECT id FROM vehicle_catalog")).OrderBy(x => x).ToArray();
        Assert.Equal(new[] { toyota.Id }, ids);
    }

    [SkippableFact]
    public async Task Etag_MatchingIfNoneMatchIs304_NonMatchingIs200WithBody()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        await SeedAsync(app, CatalogTestData.Pack(1,
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
        await SeedAsync(app, CatalogTestData.Pack(1, volvo));

        // A pack missing the required fuelKinds on its entry fails the schema.
        var invalid = CatalogTestData.Pack(2,
            new CatalogTestData.Entry(Guid.NewGuid(), "Toyota", "Corolla", FuelKinds: []));
        var refused = await PublishAsync(app, invalid);
        Assert.False(refused.IsSuccess);
        Assert.Equal(CatalogPublishErrorKind.SchemaValidationFailed, refused.Error!.Kind);

        // The refusal is at WRITE time AND the endpoint still serves the
        // previously published pack untouched - asserting the write call alone
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
        await SeedAsync(app, CatalogTestData.Pack(1, volvo));
        await SeedAsync(app, CatalogTestData.Pack(2, volvo with { TankCapacityL = 72m }));

        // The lower version (1 < current 2) is refused...
        var lower = await PublishAsync(app, CatalogTestData.Pack(1, volvo with { TankCapacityL = 73m }));
        Assert.False(lower.IsSuccess);
        Assert.Equal(CatalogPublishErrorKind.VersionNotMonotonic, lower.Error!.Kind);

        // ...and so is the equal version (2 == current 2). The >= vs > slip is
        // exactly the likely bug: if the check were >= instead of >, the equal
        // case would slip through and re-publish version 2 as a "rollback".
        var equal = await PublishAsync(app, CatalogTestData.Pack(2, volvo with { TankCapacityL = 73m }));
        Assert.False(equal.IsSuccess);
        Assert.Equal(CatalogPublishErrorKind.VersionNotMonotonic, equal.Error!.Kind);

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
    public async Task PublicEndpoint_ReachableWithoutBearer()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        // GET /catalog carries no Authorization header at all - it must serve.
        // A signed-out user's Add-car autocomplete depends on it (hard rule 1).
        using var publicRequest = new HttpRequestMessage(HttpMethod.Get, "/v1/catalog");
        Assert.Null(publicRequest.Headers.Authorization);
        var publicResponse = await client.SendAsync(publicRequest);
        Assert.Equal(HttpStatusCode.OK, publicResponse.StatusCode);
    }

    [SkippableFact]
    public async Task CatalogHasNoWriteSurface_PublishRouteIsGone()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        // The publish endpoint was removed (2026-09-01): packs are written
        // directly to the database. Asserted as 404 rather than left untested,
        // because "the route is gone" is the security property that replaced the
        // admin token - an unauthenticated POST must not find anything to reach.
        var response = await client.PostAsync("/v1/catalog/publish",
            new StringContent(CatalogTestData.Pack(1), Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [SkippableFact]
    public async Task SinceVersion_AtOrAboveTheCurrentVersion_IsAnHonestEmptyDelta()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        await SeedAsync(app, CatalogTestData.Pack(3,
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

        await SeedAsync(app, CatalogTestData.Pack(1,
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

    /// <summary>
    /// The seed migration is only useful if a device can actually receive it.
    /// A client's held version STARTS at the bundled seed pack's packVersion
    /// (VehicleCatalog.seed.json, currently 2) and it applies a pack only when
    /// packVersion is strictly greater (docs/SYNC.md "packVersion is
    /// monotonic"), so a server publishing at or below that version is
    /// invisible: every device asks since_version=2 and gets an honest empty
    /// delta. This is the regression guard for that - the seed pack and the
    /// published packs share ONE numbering space.
    /// </summary>
    [SkippableFact]
    public async Task MigrationSeedsACatalogPackAboveTheBundledSeedVersion()
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await using var _ = db;
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        using var app = await StartAsync(db.ConnectionString);

        // Exactly what a fresh device on the bundled seed pack asks for.
        var response = await GetAsync(app.Client, $"/v1/catalog?since_version={BundledSeedPackVersion}");
        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

        Assert.True(body.GetProperty("packVersion").GetInt32() > BundledSeedPackVersion,
            "a pack at or below the bundled seed's version never reaches a device");
        Assert.NotEmpty(body.GetProperty("entries").EnumerateArray());
    }

    /// <summary>ios/Sources/TankbookCore/Catalog/VehicleCatalog.seed.json -> packVersion.</summary>
    private const int BundledSeedPackVersion = 2;

    [SkippableFact]
    public async Task Publish_SuccessReportsTheVersionAndCount()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var result = await PublishAsync(app, CatalogTestData.Pack(4,
            new CatalogTestData.Entry(Guid.NewGuid(), "Volvo", "V60", Years: [2018, 2025], FuelKinds: ["petrol95", "diesel"], TankCapacityL: 71m),
            new CatalogTestData.Entry(Guid.NewGuid(), "Tesla", "Model 3", Powertrain: "ev", FuelKinds: ["electricity"], BatteryCapacityKwh: 60m),
            // Still in production: a start year and no end. This is the common
            // case in a curated pack, not an edge one.
            new CatalogTestData.Entry(Guid.NewGuid(), "Haval", "Jolion", Years: [2021, null], FuelKinds: ["petrol95"], TankCapacityL: 55m)));
        Assert.True(result.IsSuccess);
        Assert.Equal(4, result.Version);
        Assert.Equal(3, result.EntriesPublished);

        // The full round trip: years and the offer set survive exactly.
        var full = await GetAsync(client, "/v1/catalog");
        var fullBody = JsonDocument.Parse(await full.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(4, fullBody.GetProperty("packVersion").GetInt32());
        var entries = EntriesById(fullBody);
        var volvo = entries.Values.First(e => e.GetProperty("make").GetString() == "Volvo");
        Assert.Equal(new[] { 2018, 2025 }, volvo.GetProperty("years").EnumerateArray().Select(y => y.GetInt32()).ToArray());
        Assert.Equal(new[] { "petrol95", "diesel" }, volvo.GetProperty("fuelKinds").EnumerateArray().Select(f => f.GetString()).ToArray());
        Assert.Equal(71m, volvo.GetProperty("tankCapacityL").GetDecimal());

        // An open-ended line keeps its START year and reports a null end - it
        // does NOT collapse to years: null, which would lose 2021 and leave the
        // client rendering "0-" in Add-car autocomplete (docs/API.md).
        var jolion = entries.Values.First(e => e.GetProperty("make").GetString() == "Haval");
        var jolionYears = jolion.GetProperty("years").EnumerateArray().ToArray();
        Assert.Equal(2, jolionYears.Length);
        Assert.Equal(2021, jolionYears[0].GetInt32());
        Assert.Equal(JsonValueKind.Null, jolionYears[1].ValueKind);

        // A line with no range at all is still a bare null - that is what null
        // means now, and nothing else.
        var tesla = entries.Values.First(e => e.GetProperty("make").GetString() == "Tesla");
        Assert.Equal(JsonValueKind.Null, tesla.GetProperty("years").ValueKind);
    }

    private async Task<NpgsqlConnection> OpenAndMigrateAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        await ClearSeededCatalogAsync(db);
        return db;
    }

    /// <summary>
    /// Every test below owns the catalog's contents: it publishes the exact pack
    /// it then asserts on, and "the catalog is empty" is a premise several of
    /// them start from. Migration 019 seeds a real CIS pack, so a freshly
    /// migrated database is NOT empty - these tests drop that pack and reset the
    /// version, so they keep testing the endpoint rather than the seed data.
    /// That the seed itself lands, and lands above the bundled seed pack's
    /// version, is asserted once by
    /// <see cref="MigrationSeedsACatalogPackAboveTheBundledSeedVersion"/>.
    /// </summary>
    private static async Task ClearSeededCatalogAsync(NpgsqlConnection db)
    {
        await db.ExecuteAsync("DELETE FROM vehicle_catalog");
        await db.ExecuteAsync("UPDATE catalog_pack_state SET pack_version = 0 WHERE singleton = 1");
    }

    private static async Task<HttpResponseMessage> GetAsync(HttpClient client, string url)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        return await client.SendAsync(request);
    }

    /// <summary>
    /// Seeds a pack the way packs are now written: straight through
    /// <see cref="CatalogPublishService"/> against the real database. There is no
    /// publish endpoint any more (removed 2026-09-01), so these tests exercise
    /// the write path that actually exists rather than an HTTP surface that does
    /// not - and the schema and monotonic-version guards are still the ones
    /// running, because they live in the service.
    /// </summary>
    private static async Task<CatalogPublishResult> PublishAsync(CatalogTestApp app, string packJson)
    {
        using var scope = app.Services.CreateScope();
        var service = scope.ServiceProvider.GetRequiredService<CatalogPublishService>();
        return await service.PublishAsync(packJson, CancellationToken.None);
    }

    private static async Task SeedAsync(CatalogTestApp app, string packJson)
    {
        var result = await PublishAsync(app, packJson);
        Assert.True(result.IsSuccess, $"seed refused: {result.Error?.Kind} {result.Error?.Detail}");
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

    private static async Task<CatalogTestApp> StartAsync(string connectionString, int? maxDeltaEntries = null)
    {
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

        /// <summary>The host's services - how a test reaches the write path now.</summary>
        public IServiceProvider Services => _factory.Services;

        public void Dispose()
        {
            Client.Dispose();
            _factory.Dispose();
        }
    }
}
