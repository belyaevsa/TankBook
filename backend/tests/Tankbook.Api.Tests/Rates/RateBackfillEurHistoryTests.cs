using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// RV.135 L2: past EUR dates through the whole production path. ECB offers no
/// per-date query, so the real <see cref="EcbRateFeed"/> fetches its history
/// files; these tests serve REAL ECB eurofxref rows (captured 2026-09-08,
/// trimmed to the tested days) over a stubbed HttpClient and drive real Postgres.
/// The demand is queued the way /rates/pack queues it, a pass publishes it, and
/// the next request is served - never just "was enqueued".
///
/// "Today" is pinned to 2026-08-26 so a 2015 date is firmly inside the full
/// history file's range and the daily file cannot accidentally answer it.
/// </summary>
public class RateBackfillEurHistoryTests : IClassFixture<PostgresFixture>
{
    private const string DailyFixture = "ecb-eurofxref-daily-2026-08-26.xml";
    private const string RecentFixture = "ecb-eurofxref-hist-90d-2026-08-26.xml";
    private const string FullFixture = "ecb-eurofxref-hist-2015.xml";

    // Real ECB values for the fixture dates (see the fixture file).
    private static readonly DateOnly Today = new(2026, 8, 26);
    private static readonly DateOnly Day2015A = new(2015, 6, 15);
    private static readonly DateOnly Day2015B = new(2015, 6, 16);
    private static readonly DateOnly Day2015C = new(2015, 6, 19);
    private static readonly decimal Usd2015A = 1.1218m;
    private static readonly decimal Usd2015B = 1.1215m;
    private static readonly decimal Usd2015C = 1.1299m;

    private readonly PostgresFixture _fixture;

    public RateBackfillEurHistoryTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static RateBackfillEurHistoryTests()
    {
        DapperTypeHandlers.Register();
    }

    /// <summary>
    /// The row this fix exists for: a 2015 EUR date asked through /rates/pack
    /// (the demand a multi-year import's drain generates), published by a
    /// backfill pass, and served on the next request. A test that stopped at
    /// "it was enqueued" would prove nothing - the rate has to come back.
    /// </summary>
    [SkippableFact]
    public async Task ADecadeOldEurDate_AskedThroughRatesPack_IsPublishedByABackfillPass_AndServedOnTheNextRequest()
    {
        _fixture.RequireAvailable();
        await using var db = await CreateMigratedAsync();
        var handler = EcbHandler();
        using var app = await StartAppAsync(db.ConnectionString, handler);
        using var client = app.Client;

        // The device asks for the exact date its imported entry needs.
        var request = await client.GetAsync($"/v1/rates/pack?from={Day2015B:yyyy-MM-dd}&to={Day2015B:yyyy-MM-dd}&base=EUR");
        Assert.Equal(HttpStatusCode.OK, request.StatusCode);

        // The response returns what exists now - nothing yet.
        Assert.Equal(0, await QuoteCountAsync(client, Day2015B));

        // The background pass (driven directly - no timer in test hosts) fetches
        // the queued date and publishes it.
        using (var scope = app.Services.CreateScope())
        {
            var backfill = scope.ServiceProvider.GetRequiredService<RateBackfillService>();
            var result = await backfill.ProcessPendingAsync(CancellationToken.None);

            Assert.Equal(1, result.Processed);
            Assert.Equal(8, result.Published); // the fixture row carries 8 currencies
            Assert.Equal(0, result.Answered);
        }

        // The device's next request is served the rate.
        var body = await client.GetStringAsync($"/v1/rates?date={Day2015B:yyyy-MM-dd}&base=EUR");
        using var doc = JsonDocument.Parse(body);
        var usd = FindUsd(doc);
        Assert.True(usd is not null, "no USD quote served after the backfill pass");
        Assert.Equal(Usd2015B, usd.Value.GetProperty("rate").GetDecimal());
        Assert.Equal(RateSources.Ecb, usd.Value.GetProperty("source").GetString());

        // The whole pass made exactly one upstream request - the full history
        // file, fetched once and reused for every date it covers.
        var upstream = Assert.Single(handler.Requests);
        Assert.Contains("eurofxref-hist.xml", upstream.AbsolutePath, StringComparison.Ordinal);
    }

    /// <summary>
    /// The stored value for each date must be THAT date's row in the fixture,
    /// not today's and not the file's other date. The fixture holds two adjacent
    /// 2015 days with different USD values, so a feed serving the wrong row -
    /// the failure this fix must not reintroduce - puts a wrong number into
    /// someone's cost history and fails here.
    /// </summary>
    [SkippableFact]
    public async Task TheStoredRate_ForEachRequestedDate_IsThatDatesOwnRow()
    {
        _fixture.RequireAvailable();
        await using var db = await CreateMigratedAsync();
        var (feed, _) = EcbFeed();
        var backfill = BuildBackfill(db, feed);

        Assert.Equal(2, await backfill.RecordRequestAsync(Day2015A, Day2015B, "EUR", CancellationToken.None));

        var result = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(2, result.Processed);
        Assert.Equal(16, result.Published); // two dates x the fixture row's 8 currencies
        Assert.Equal(0, result.Answered);

        var rows = await ReadRatesAsync(db, "EUR");
        var usdA = rows.Single(r => r.Date == Day2015A && r.Quote == "USD");
        var usdB = rows.Single(r => r.Date == Day2015B && r.Quote == "USD");
        Assert.Equal(Usd2015A, usdA.Rate);
        Assert.Equal(Usd2015B, usdB.Rate);
        Assert.False(RateSources.IsCarried(usdA.Source));
        Assert.False(RateSources.IsCarried(usdB.Source));
    }

    /// <summary>
    /// One pass over fifty historical dates must make a bounded number of
    /// upstream requests - the history file is fetched once per pass and every
    /// date it covers is answered from it (docs/SCHEMA.md). Re-downloading the
    /// full history per date is the trap; the count is the evidence.
    /// </summary>
    [SkippableFact]
    public async Task OnePassOverManyHistoricalDates_MakesABoundedNumberOfUpstreamRequests()
    {
        _fixture.RequireAvailable();
        await using var db = await CreateMigratedAsync();
        var (feed, handler) = EcbFeed();
        var backfill = BuildBackfill(db, feed);

        // 50 consecutive dates in 2015 ending at the fixture's newest row - the
        // real full-history file extends to ~today, so a 2015 demand never
        // exceeds the file's newest row and one fetch serves the whole pass.
        // Dates past the fixture's top row would legitimately refetch (a stale
        // file is exactly when the feed must go back upstream), which is a
        // different property, not the one being pinned here.
        var last = Day2015C;
        var dates = new List<DateOnly>();
        for (var day = last.AddDays(-49); dates.Count < 50; day = day.AddDays(1))
        {
            dates.Add(day);
        }
        Assert.Equal(new DateOnly(2015, 5, 1), dates[0]);

        Assert.Equal(50, await new RateRepository(db).RecordPendingAsync(dates, "EUR", CancellationToken.None));

        var result = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(50, result.Processed);
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));

        // Exactly one upstream request served the whole batch.
        var upstream = Assert.Single(handler.Requests);
        Assert.Contains("eurofxref-hist.xml", upstream.AbsolutePath, StringComparison.Ordinal);

        // The fixture's real working days among the 50 published; nothing was guessed.
        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Equal(Usd2015A, rows.Single(r => r.Date == Day2015A && r.Quote == "USD").Rate);
        Assert.Equal(Usd2015B, rows.Single(r => r.Date == Day2015B && r.Quote == "USD").Rate);
        Assert.Equal(Usd2015C, rows.Single(r => r.Date == Day2015C && r.Quote == "USD").Rate);
    }

    /// <summary>
    /// A weekend the history genuinely lacks is resolved by the carry rule, not
    /// guessed: the fixture publishes Friday 2015-06-19; Saturday and Sunday
    /// take Friday's rate as :carried-forward rows within the 14-day window.
    /// </summary>
    [SkippableFact]
    public async Task AWeekendTheHistoryLacks_ResolvesByTheCarryRule_NeverGuessed()
    {
        _fixture.RequireAvailable();
        await using var db = await CreateMigratedAsync();
        var (feed, _) = EcbFeed();
        var backfill = BuildBackfill(db, feed);

        var saturday = Day2015C.AddDays(1); // 2015-06-20
        var sunday = Day2015C.AddDays(2); // 2015-06-21

        var result = await backfill.BackfillRangeAsync(Day2015C, sunday, "EUR", CancellationToken.None);
        Assert.Equal(8, result.Published); // Friday's row
        Assert.Equal(16, result.CarriedForward); // both weekend days, all 8 currencies

        var rows = await ReadRatesAsync(db, "EUR");
        var friday = rows.Single(r => r.Date == Day2015C && r.Quote == "USD");
        var satUsd = rows.Single(r => r.Date == saturday && r.Quote == "USD");
        var sunUsd = rows.Single(r => r.Date == sunday && r.Quote == "USD");
        Assert.Equal(Usd2015C, friday.Rate);
        Assert.False(RateSources.IsCarried(friday.Source));
        Assert.Equal(Usd2015C, satUsd.Rate);
        Assert.Equal(RateSources.Carried(RateSources.Ecb), satUsd.Source);
        Assert.Equal(Usd2015C, sunUsd.Rate);
        Assert.Equal(RateSources.Carried(RateSources.Ecb), sunUsd.Source);
    }

    private async Task<NpgsqlConnection> CreateMigratedAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    /// <summary>The real feed behind a stub handler serving the three ECB files by path.</summary>
    private static (EcbRateFeed Feed, PathRoutingHandler Handler) EcbFeed()
    {
        var handler = EcbHandler();
        var services = new ServiceCollection();
        services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => handler);
        var clock = new MutableTimeProvider(new DateTimeOffset(Today.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero));
        var feed = new EcbRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>(), clock);
        return (feed, handler);
    }

    private static PathRoutingHandler EcbHandler() =>
        new(
        [
            ("eurofxref-daily.xml", DailyFixture),
            ("eurofxref-hist-90d.xml", RecentFixture),
            ("eurofxref-hist.xml", FullFixture),
        ]);

    /// <summary>
    /// The production host with the feed boundary stubbed: the real
    /// <see cref="EcbRateFeed"/> (so the URL choice, the parse and the guard are
    /// the production ones), its HttpClient pointed at the fixture handler, and
    /// the other feeds removed so the test host never reaches cbr.ru/nbk.
    /// </summary>
    private static async Task<EcbApp> StartAppAsync(string connectionString, PathRoutingHandler handler)
    {
        var clock = new MutableTimeProvider(new DateTimeOffset(Today.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero));
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b
                .UseEnvironment("Testing")
                .UseSetting("ConnectionStrings:Postgres", connectionString)
                .ConfigureServices(services =>
                {
                    services.Replace(ServiceDescriptor.Singleton<TimeProvider>(clock));
                    services.RemoveAll<IRateFeed>();
                    services.AddSingleton<IRateFeed>(sp =>
                        new EcbRateFeed(sp.GetRequiredService<IHttpClientFactory>(), sp.GetRequiredService<TimeProvider>()));
                    services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => handler);
                }));

        return new EcbApp(factory, factory.CreateClient());
    }

    private static RateBackfillService BuildBackfill(NpgsqlConnection db, params IRateFeed[] feeds)
    {
        var repository = new RateRepository(db);
        var options = Microsoft.Extensions.Options.Options.Create(new RateOptions
        {
            BaseCurrencies = ["EUR"],
            CarryBackWindowDays = 14,
            BackfillBatchSize = 50,
        });
        return new RateBackfillService(repository, feeds, options, NullLogger<RateBackfillService>.Instance);
    }

    private static async Task<int> QuoteCountAsync(HttpClient client, DateOnly date)
    {
        var body = await client.GetStringAsync($"/v1/rates?date={date:yyyy-MM-dd}&base=EUR");
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.GetProperty("quotes").GetArrayLength();
    }

    private static JsonElement? FindUsd(JsonDocument doc)
    {
        foreach (var quote in doc.RootElement.GetProperty("quotes").EnumerateArray())
        {
            if (quote.GetProperty("quote").GetString() == "USD")
            {
                return quote.Clone();
            }
        }

        return null;
    }

    private static async Task<int> CountAsync(NpgsqlConnection db, string table)
        => await db.QuerySingleAsync<int>($"SELECT count(*) FROM {table}");

    private static async Task<List<DbRate>> ReadRatesAsync(NpgsqlConnection db, string baseCurrency)
    {
        var rows = await db.QueryAsync<DbRate>(
            """
            SELECT date AS Date, base AS Base, quote AS Quote, rate AS Rate, source AS Source,
                   deleted_at IS NOT NULL AS Deleted
            FROM exchange_rates
            WHERE base = @Base
            ORDER BY date, quote
            """,
            new { Base = baseCurrency });
        return rows.ToList();
    }

    private sealed record DbRate(DateOnly Date, string Base, string Quote, decimal Rate, string Source, bool Deleted);

    private sealed class EcbApp : IDisposable
    {
        private readonly WebApplicationFactory<Program> _factory;

        public EcbApp(WebApplicationFactory<Program> factory, HttpClient client)
        {
            _factory = factory;
            Client = client;
        }

        public IServiceProvider Services => _factory.Services;

        public HttpClient Client { get; }

        public void Dispose()
        {
            Client.Dispose();
            _factory.Dispose();
        }
    }
}
