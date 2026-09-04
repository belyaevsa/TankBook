using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// L2 tests for the demand-driven rate backfill (docs/SCHEMA.md "Reference data
/// -> Exchange rates", RV.32) against real Postgres via Testcontainers. The feed
/// is a recording double for the arithmetic cases and the REAL captured cbr.ru
/// response for the published/earlier-document cases; the repository, the upsert,
/// the carry-back and the 14-day bound are all real. The service is driven
/// directly - the hosted timer that would run it is not registered in test hosts.
/// </summary>
public class RateBackfillTests : IClassFixture<PostgresFixture>
{
    private static readonly DateOnly Friday = new(2026, 8, 21);
    private static readonly DateOnly Saturday = new(2026, 8, 22);
    private static readonly DateOnly Sunday = new(2026, 8, 23);

    private static readonly DateOnly NewYearsEve = new(2025, 12, 31);
    private static readonly DateOnly NewYearHoliday = new(2026, 1, 7);
    private static readonly DateOnly FirstJanuaryDocument = new(2026, 1, 13);

    private readonly PostgresFixture _fixture;

    public RateBackfillTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static RateBackfillTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task APastDateWithNoRow_IsFetchedAndStoredPublished_FromARealDocument()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The REAL cbr.ru response for 15.08.2026, which carries its own document
        // (Date="15.08.2026", EUR 97.5141). A backfill for that date must fetch it
        // and store it PUBLISHED - the value is a real document, not interpolation.
        var feed = CisFeedServing("date_req=15/08/2026", "cbr-xml-daily-2026-08-15-windows1251.xml");
        var backfill = BuildBackfill(db, feed);

        await backfill.BackfillRangeAsync(new DateOnly(2026, 8, 15), new DateOnly(2026, 8, 15), "EUR", CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        var row = Assert.Single(rows, r => r.Quote == "RUB");
        Assert.Equal(97.5141m, row.Rate);
        Assert.Equal(RateSources.Cis, row.Source);
        Assert.False(RateSources.IsCarried(row.Source));
        Assert.False(row.Deleted);
    }

    [SkippableFact]
    public async Task AGapDate_IsStoredCarriedForward_FromTheMostRecentEarlierRate()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();
        await SeedPublishedAsync(db, Friday, "USD", 1.10m);

        // Friday publishes, the weekend does not. The backfill is asked for the
        // whole span; the gap days must carry Friday's value, marked carried and
        // holding the right rate - not merely existing.
        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == Friday ? [new RateQuote("USD", 1.10m)] : []);
        var backfill = BuildBackfill(db, feed);

        await backfill.BackfillRangeAsync(Friday, Sunday, "EUR", CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == Saturday && r.Quote == "USD" && r.Rate == 1.10m && RateSources.IsCarried(r.Source) && r.Source == RateSources.Carried(RateSources.Ecb));
        Assert.Contains(rows, r => r.Date == Sunday && r.Quote == "USD" && r.Rate == 1.10m && RateSources.IsCarried(r.Source) && r.Source == RateSources.Carried(RateSources.Ecb));
        // Friday's own row stays published, not carried.
        Assert.Contains(rows, r => r.Date == Friday && r.Quote == "USD" && r.Source == RateSources.Ecb && !RateSources.IsCarried(r.Source));
    }

    [SkippableFact]
    public async Task ADateBeyondFourteenDaysPastTheLastRate_IsLeftAbsent_NotInvented()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();
        await SeedPublishedAsync(db, Friday, "USD", 1.10m);

        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((_, _) => []);
        var backfill = BuildBackfill(db, feed);

        var farPast = Friday.AddDays(20);
        await backfill.BackfillRangeAsync(farPast, farPast, "EUR", CancellationToken.None);

        // The only earlier USD rate is 20 days back - outside the 14-day window.
        // The date must stay absent, not silently take an unrelated rate.
        var rows = await ReadRatesAsync(db, "EUR");
        Assert.DoesNotContain(rows, r => r.Date == farPast && r.Quote == "USD");
    }

    [SkippableFact]
    public async Task TheNewYearHoliday_FetchesTheDecemberDocumentAsThatDaysRate()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The REAL captured New Year response: asking cbr.ru for 04.01.2026 (or
        // any holiday date) returns the document dated 31.12.2025, EUR 92.0938.
        // Per RV.20 that document IS the holiday's rate, stored published.
        var feed = CisFeedServing("date_req=07/01/2026", "cbr-xml-daily-2026-01-04-holiday-windows1251.xml");
        var backfill = BuildBackfill(db, feed);

        await backfill.BackfillRangeAsync(NewYearHoliday, NewYearHoliday, "EUR", CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        var row = Assert.Single(rows, r => r.Quote == "RUB");
        Assert.Equal(NewYearHoliday, row.Date);
        Assert.Equal(92.0938m, row.Rate);
        Assert.Equal(RateSources.Cis, row.Source);
        Assert.False(RateSources.IsCarried(row.Source));
    }

    [SkippableFact]
    public async Task TheFirstJanuaryDocument_IsNotSmearedWithTheHolidayRate()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The 13.01.2026 document is the first January one; its rate is its own,
        // not 31.12's. A backfill over the window must store each date's value,
        // proving the fetch does not let the holiday rate leak onto 13.01.
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((date, _) =>
            date <= FirstJanuaryDocument.AddDays(-1)
                ? [new RateQuote("RUB", 92.0938m)]
                : [new RateQuote("RUB", 93.5000m)]);
        var backfill = BuildBackfill(db, feed);

        await backfill.BackfillRangeAsync(NewYearHoliday, FirstJanuaryDocument, "EUR", CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Equal(92.0938m, Assert.Single(rows, r => r.Date == NewYearHoliday && r.Quote == "RUB").Rate);
        Assert.Equal(93.5000m, Assert.Single(rows, r => r.Date == FirstJanuaryDocument && r.Quote == "RUB").Rate);
    }

    [SkippableFact]
    public async Task CarryBack_ResolvesAThirteenDayGap_ButNotFifteen()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();
        await SeedPublishedAsync(db, NewYearsEve, "RUB", 92.0938m, RateSources.Cis);

        // The feed returns nothing for any of these dates (the carry-back's job,
        // not the feed's). A 7-day and a 13-day gap both resolve from 31.12; a
        // 15-day gap does not - that is the measured 14-day bound (the New Year
        // gap is 13 days, so 14 covers it and 15 is deliberately out).
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => []);
        var backfill = BuildBackfill(db, feed);

        var day7 = NewYearsEve.AddDays(7);
        var day13 = NewYearsEve.AddDays(13);
        var day15 = NewYearsEve.AddDays(15);
        await backfill.BackfillRangeAsync(day7, day15, "EUR", CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == day7 && r.Quote == "RUB" && r.Rate == 92.0938m && RateSources.IsCarried(r.Source));
        Assert.Contains(rows, r => r.Date == day13 && r.Quote == "RUB" && r.Rate == 92.0938m && RateSources.IsCarried(r.Source));
        Assert.DoesNotContain(rows, r => r.Date == day15 && r.Quote == "RUB");
    }

    [SkippableFact]
    public async Task ProcessPending_FetchesTheQueuedDemandAndSettlesIt()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The production path: a demand is queued (as GET /rates/pack does), then
        // the background pass fetches it and removes it from the queue. This pins
        // the queue round-trip - the DateOnly batch read and the settle - which
        // BackfillRangeAsync never touches.
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => [new RateQuote("RUB", 90.0m)]);
        var backfill = BuildBackfill(db, feed);

        var day = new DateOnly(2026, 9, 2);
        await new RateRepository(db).RecordPendingAsync([day], "EUR", CancellationToken.None);

        var result = await backfill.ProcessPendingAsync(CancellationToken.None);

        Assert.Equal(1, result.Processed);
        Assert.Equal(1, result.Published);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == day && r.Quote == "RUB" && r.Rate == 90.0m && r.Source == RateSources.Cis && !RateSources.IsCarried(r.Source));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM rate_backfill"));
    }

    [SkippableFact]
    public async Task AnUnfillableDate_IsAnsweredOnce_AndTheQueueIsEmptyOnTheSecondPass()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // A date no feed can fill: every feed answers empty (no document, no exception).
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => []);
        var backfill = BuildBackfill(db, feed);

        var day = new DateOnly(2026, 9, 2);

        // The pack trigger queues the date (the device asked for a date we have no rate for).
        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, "EUR", CancellationToken.None));

        // First pass: the feed is asked, answers empty, and the date is settled.
        var first = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, first.Processed);
        Assert.Equal(0, first.Published);
        Assert.Equal(0, first.CarriedForward);
        Assert.Equal(1, first.Answered);

        // The device re-asks on its next refresh. The date is answered now, so the
        // pack must NOT re-enqueue it.
        Assert.Equal(0, await backfill.RecordRequestAsync(day, day, "EUR", CancellationToken.None));

        // Second pass: the queue is EMPTY - the date did not reappear.
        var second = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(0, second.Processed);
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM rate_backfill"));
    }

    [SkippableFact]
    public async Task AFillableDate_IsStillQueuedAndPublished_NotAnswered()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The counterpart to the unfillable case: a date a feed CAN fill must still
        // be enqueued by the pack and published - the fix must not over-correct into
        // answering a fillable date empty.
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => [new RateQuote("RUB", 90.0m)]);
        var backfill = BuildBackfill(db, feed);

        var day = new DateOnly(2026, 9, 2);

        // The pack still enqueues a date it has no rate for (the messenger is intact).
        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, "EUR", CancellationToken.None));

        var result = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, result.Published);
        Assert.Equal(0, result.Answered);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == day && r.Quote == "RUB" && r.Rate == 90.0m && r.Source == RateSources.Cis && !RateSources.IsCarried(r.Source));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM rate_backfill"));
    }

    [SkippableFact]
    public async Task ADateOneFeedCoversAndAnotherNeverWill_IsFilledAndNotReenqueued()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The production shape: cis serves the date, ecb structurally never will
        // (its daily file carries only today, so a past date answers empty). The
        // date must be filled from cis, have ecb answered empty, and NOT be
        // re-enqueued forever - the granularity both ends now agree on.
        var cis = new RecordingRateFeed(RateSources.Cis);
        cis.SetHandler((_, _) => [new RateQuote("RUB", 90.0m)]);
        var ecb = new RecordingRateFeed(RateSources.Ecb);
        ecb.SetHandler((_, _) => []);
        var backfill = BuildBackfill(db, cis, ecb);

        var day = new DateOnly(2026, 9, 2);

        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, "EUR", CancellationToken.None));

        var result = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, result.Published);
        Assert.Equal(1, result.Answered);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == day && r.Quote == "RUB" && r.Rate == 90.0m && r.Source == RateSources.Cis && !RateSources.IsCarried(r.Source));

        // cis filled the date and ecb answered empty, so the next pack request must
        // not re-enqueue it (the old code did, forever).
        Assert.Equal(0, await backfill.RecordRequestAsync(day, day, "EUR", CancellationToken.None));
        Assert.Equal(0, await db.QuerySingleAsync<int>("SELECT count(*) FROM rate_backfill"));
    }

    [SkippableFact]
    public async Task ADateAnsweredEmpty_IsReopenedWhenAnEarlierAnchorArrives()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // A gap date asked before its anchor exists is answered empty; when the
        // anchor arrives later (a second request), publishing it must reopen the
        // answered gap so the next pass carries it back - a fix that never reopens
        // would leave the date absent forever.
        var anchor = new DateOnly(2026, 9, 1);
        var day = new DateOnly(2026, 9, 8); // 7 days after the anchor - inside the 14-day window
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((date, _) => date == anchor ? [new RateQuote("RUB", 90.0m)] : []);
        var backfill = BuildBackfill(db, feed);

        // The gap date is asked first, with no anchor anywhere -> answered empty.
        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, "EUR", CancellationToken.None));
        var first = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, first.Answered);
        Assert.Equal(0, first.Published);

        // The anchor arrives later (a second device asks for it).
        Assert.Equal(1, await backfill.RecordRequestAsync(anchor, anchor, "EUR", CancellationToken.None));
        var anchorPass = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, anchorPass.Published);

        // Publishing the anchor reopened the answered gap date; the next pass
        // carries it back from the anchor.
        var reopened = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, reopened.CarriedForward);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == day && r.Quote == "RUB" && r.Rate == 90.0m && RateSources.IsCarried(r.Source));
    }

    private async Task<NpgsqlConnection> OpenDatabaseAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static RateBackfillService BuildBackfill(NpgsqlConnection db, params IRateFeed[] feeds)
    {
        var repository = new RateRepository(db);
        var options = Microsoft.Extensions.Options.Options.Create(new RateOptions
        {
            BaseCurrencies = ["EUR"],
            CarryBackWindowDays = 14,
        });
        return new RateBackfillService(repository, feeds, options, NullLogger<RateBackfillService>.Instance);
    }

    private static async Task SeedPublishedAsync(NpgsqlConnection db, DateOnly date, string quote, decimal rate)
        => await SeedPublishedAsync(db, date, quote, rate, RateSources.Ecb);

    private static async Task SeedPublishedAsync(NpgsqlConnection db, DateOnly date, string quote, decimal rate, string source)
    {
        var repository = new RateRepository(db);
        await repository.UpsertAsync(new RateInsert(date, "EUR", quote, rate, source), CancellationToken.None);
    }

    /// <summary>The real <see cref="CisRateFeed"/> behind a routing handler that serves the captured fixture when the request carries the marker, like cbr.ru does.</summary>
    private static CisRateFeed CisFeedServing(string marker, string fixture)
    {
        var handler = new FixtureRoutingHandler("cbr-xml-daily-windows1251.xml", (marker, fixture));
        var services = new ServiceCollection();
        services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => handler);
        return new CisRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>());
    }

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
}
