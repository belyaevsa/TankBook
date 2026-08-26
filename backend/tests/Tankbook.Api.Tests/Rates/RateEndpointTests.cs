using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// L2 tests for GET /v1/rates and GET /v1/rates/pack (docs/API.md reference
/// data) against real Postgres. The clock is pinned so "today" is deterministic;
/// the database, the endpoint wiring and the cache headers are real - only the
/// feed is absent (these endpoints only read). No request carries a bearer token,
/// which is the point: these are public, CDN-cacheable reference data.
/// </summary>
public class RateEndpointTests : IClassFixture<PostgresFixture>
{
    private static readonly DateOnly Today = new(2026, 8, 26);
    private static readonly DateOnly Yesterday = new(2026, 8, 25);

    private readonly PostgresFixture _fixture;

    public RateEndpointTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static RateEndpointTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task GetRates_PastDateIsImmutable_TodayIsNot()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        await SeedAsync(db, Yesterday, ("USD", 1.10m));
        await SeedAsync(db, Today, ("USD", 1.12m));

        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var past = await client.GetAsync($"/v1/rates?date={Yesterday:yyyy-MM-dd}&base=EUR");
        Assert.Equal(HttpStatusCode.OK, past.StatusCode);
        Assert.Contains("immutable", past.Headers.CacheControl?.ToString());

        var today = await client.GetAsync($"/v1/rates?date={Today:yyyy-MM-dd}&base=EUR");
        Assert.Equal(HttpStatusCode.OK, today.StatusCode);
        Assert.DoesNotContain("immutable", today.Headers.CacheControl?.ToString());
    }

    [SkippableFact]
    public async Task GetRates_ReturnsAllQuotesForTheDate()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        await SeedAsync(db, Yesterday, ("USD", 1.10m), ("RUB", 90.0m));

        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var response = await client.GetAsync($"/v1/rates?date={Yesterday:yyyy-MM-dd}&base=EUR");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("EUR", doc.RootElement.GetProperty("base").GetString());
        var quotes = doc.RootElement.GetProperty("quotes");
        Assert.Equal(2, quotes.GetArrayLength());
    }

    [SkippableFact]
    public async Task GetRates_DateWithNoData_ReturnsEmptyQuotes_NeverInventingARate()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();

        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var response = await client.GetAsync($"/v1/rates?date={Yesterday:yyyy-MM-dd}&base=EUR");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(0, doc.RootElement.GetProperty("quotes").GetArrayLength());
    }

    [SkippableFact]
    public async Task GetRatesPack_ReturnsTheFullInclusiveRange()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        var from = Yesterday.AddDays(-2);
        await SeedAsync(db, from, ("USD", 1.08m));
        await SeedAsync(db, Yesterday, ("USD", 1.10m));

        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var response = await client.GetAsync($"/v1/rates/pack?from={from:yyyy-MM-dd}&to={Yesterday:yyyy-MM-dd}&base=EUR");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var rates = doc.RootElement.GetProperty("rates");
        Assert.Equal(2, rates.GetArrayLength());
        var dates = rates.EnumerateArray().Select(e => e.GetProperty("date").GetString()).ToHashSet();
        Assert.Contains(from.ToString("yyyy-MM-dd"), dates);
        Assert.Contains(Yesterday.ToString("yyyy-MM-dd"), dates);
    }

    [SkippableFact]
    public async Task GetRatesPack_AbsurdRange_IsRejected()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();

        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        var response = await client.GetAsync("/v1/rates/pack?from=2020-01-01&to=2026-01-01&base=EUR");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [SkippableFact]
    public async Task BothEndpoints_AreReachableWithoutABearerToken()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenAndMigrateAsync();
        await SeedAsync(db, Yesterday, ("USD", 1.10m));

        using var app = await StartAsync(db.ConnectionString);
        using var client = app.Client;

        using var single = new HttpRequestMessage(HttpMethod.Get, $"/v1/rates?date={Yesterday:yyyy-MM-dd}&base=EUR");
        Assert.Null(single.Headers.Authorization);
        var singleResponse = await client.SendAsync(single);
        Assert.Equal(HttpStatusCode.OK, singleResponse.StatusCode);

        using var pack = new HttpRequestMessage(HttpMethod.Get, $"/v1/rates/pack?from={Yesterday:yyyy-MM-dd}&to={Yesterday:yyyy-MM-dd}&base=EUR");
        Assert.Null(pack.Headers.Authorization);
        var packResponse = await client.SendAsync(pack);
        Assert.Equal(HttpStatusCode.OK, packResponse.StatusCode);
    }

    private async Task<NpgsqlConnection> OpenAndMigrateAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static async Task SeedAsync(NpgsqlConnection db, DateOnly date, params (string Quote, decimal Rate)[] quotes)
    {
        foreach (var (quote, rate) in quotes)
        {
            await db.ExecuteAsync(
                "INSERT INTO exchange_rates (date, base, quote, rate, source) VALUES (@Date, 'EUR', @Quote, @Rate, 'ecb')",
                new { Date = date, Quote = quote, Rate = rate });
        }
    }

    private static async Task<RateTestApp> StartAsync(string connectionString)
    {
        var clock = new MutableTimeProvider(new DateTimeOffset(Today.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero));
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b
                .UseEnvironment("Testing")
                .UseSetting("ConnectionStrings:Postgres", connectionString)
                .ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<TimeProvider>(clock));
                }));

        return new RateTestApp(factory, factory.CreateClient());
    }

    private sealed class RateTestApp : IDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;

        public RateTestApp(WebApplicationFactory<Program> factory, HttpClient client)
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
