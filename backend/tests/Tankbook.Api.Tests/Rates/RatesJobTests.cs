using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// L2 tests for the daily rates job (docs/SCHEMA.md "Reference data -> Exchange
/// rates") against real Postgres via Testcontainers. The feed is a recording
/// double and the clock is settable, but the repository, the upsert, the
/// carry-forward and the append-only/correction semantics are all real. The job
/// is driven directly - the timer that would run it on a schedule is not
/// registered in test hosts.
/// </summary>
public class RatesJobTests : IClassFixture<PostgresFixture>
{
    private static readonly DateOnly Friday = new(2026, 8, 21);
    private static readonly DateOnly Saturday = new(2026, 8, 22);
    private static readonly DateOnly Sunday = new(2026, 8, 23);
    private static readonly DateOnly Monday = new(2026, 8, 24);

    private readonly PostgresFixture _fixture;

    public RatesJobTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static RatesJobTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task WeekendCarryForward_WritesRowsDatedTheGapDays()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == Friday ? PublishedQuotes() : []);
        var clock = new MutableTimeProvider(Utc(Friday));
        var job = BuildJob(db, clock, feed);

        await job.RunAsync(CancellationToken.None);

        // The job runs again on Sunday, when nothing is published; carry-forward
        // must materialise Saturday and Sunday rows dated those exact days.
        clock.SetUtcNow(Utc(Sunday));
        feed.SetHandler((_, _) => []);
        await job.RunAsync(CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        Assert.Contains(rows, r => r.Date == Saturday && r.Quote == "USD" && r.Rate == 1.10m && !r.Deleted && RateSources.IsCarried(r.Source));
        Assert.Contains(rows, r => r.Date == Sunday && r.Quote == "USD" && r.Rate == 1.10m && !r.Deleted && RateSources.IsCarried(r.Source));
        Assert.Contains(rows, r => r.Date == Saturday && r.Quote == "RUB" && r.Rate == 90.0m && !r.Deleted && RateSources.IsCarried(r.Source));
        Assert.Contains(rows, r => r.Date == Sunday && r.Quote == "RUB" && r.Rate == 90.0m && !r.Deleted && RateSources.IsCarried(r.Source));
    }

    [SkippableFact]
    public async Task HolidayCarryForward_FillsEveryDayOfAMultiDayGap()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == Monday ? PublishedQuotes() : []);
        var clock = new MutableTimeProvider(Utc(Monday));
        var job = BuildJob(db, clock, feed);

        await job.RunAsync(CancellationToken.None);

        // A week of holidays: the job next runs on the following Sunday, and every
        // day in between must carry Monday's value, dated itself.
        var holidayEnd = Monday.AddDays(6);
        clock.SetUtcNow(Utc(holidayEnd));
        feed.SetHandler((_, _) => []);
        await job.RunAsync(CancellationToken.None);

        var rows = await ReadRatesAsync(db, "EUR");
        for (var day = Monday.AddDays(1); day <= holidayEnd; day = day.AddDays(1))
        {
            Assert.Contains(rows, r => r.Date == day && r.Quote == "USD" && r.Rate == 1.10m && !r.Deleted && RateSources.IsCarried(r.Source));
        }
    }

    [SkippableFact]
    public async Task RunTwice_LeavesExactlyOneRowPerKey_WithIdenticalValues()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == Friday ? PublishedQuotes() : []);
        var clock = new MutableTimeProvider(Utc(Friday));
        var job = BuildJob(db, clock, feed);

        await job.RunAsync(CancellationToken.None);
        await job.RunAsync(CancellationToken.None);

        var usd = (await ReadRatesAsync(db, "EUR")).Where(r => r.Quote == "USD" && r.Date == Friday).ToList();
        Assert.Single(usd);
        Assert.Equal(1.10m, usd[0].Rate);

        var count = await db.ExecuteScalarAsync<int>(
            "SELECT count(*) FROM exchange_rates WHERE date = @Date AND base = @Base",
            new { Date = Friday, Base = "EUR" });
        Assert.Equal(2, count); // USD + RUB, once each - no duplicates.
    }

    [SkippableFact]
    public async Task RefetchWithDifferentValue_DoesNotRewritePublishedRow()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == Friday ? [new RateQuote("USD", 1.10m)] : []);
        var clock = new MutableTimeProvider(Utc(Friday));
        var job = BuildJob(db, clock, feed);

        await job.RunAsync(CancellationToken.None);

        // A re-fetch the same day returns a different value; the published row
        // must survive unchanged (append-only - hard rule 3's snapshot story).
        feed.SetHandler((date, _) => date == Friday ? [new RateQuote("USD", 1.20m)] : []);
        await job.RunAsync(CancellationToken.None);

        var usd = (await ReadRatesAsync(db, "EUR")).Where(r => r.Quote == "USD").ToList();
        Assert.Single(usd);
        Assert.Equal(1.10m, usd[0].Rate);
        Assert.False(usd[0].Deleted);
    }

    [SkippableFact]
    public async Task Correction_SoftDeleteThenRefetch_ProducesCorrectedActiveRowAndKeepsSoftDeletedOriginal()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == Friday ? [new RateQuote("USD", 1.10m)] : []);
        var clock = new MutableTimeProvider(Utc(Friday));
        var job = BuildJob(db, clock, feed);

        await job.RunAsync(CancellationToken.None);

        // Manual correction: soft-delete the bad row, then re-fetch with the good
        // value. The soft-deleted row stays put and the corrected row is a fresh,
        // live row beside it - never an in-place rewrite.
        var repository = new RateRepository(db);
        Assert.Equal(1, await repository.SoftDeleteAsync(Friday, "EUR", "USD", CancellationToken.None));

        feed.SetHandler((date, _) => date == Friday ? [new RateQuote("USD", 1.20m)] : []);
        await job.RunAsync(CancellationToken.None);

        var usd = (await ReadRatesAsync(db, "EUR")).Where(r => r.Quote == "USD").ToList();
        Assert.Equal(2, usd.Count);
        Assert.Contains(usd, r => r.Deleted && r.Rate == 1.10m);
        Assert.Contains(usd, r => !r.Deleted && r.Rate == 1.20m);
    }

    /// <summary>
    /// RV.138: a decade-old anchor must not make one pass insert a row per gap
    /// day for ~4,000 days. The horizon bounds the walk to the window a device
    /// can ask for, the anchor at the horizon start still holds the value in
    /// force, and the old row itself is untouched. Removing the horizon makes
    /// <c>CarriedForward</c> thousands, not at most <c>horizon x quotes</c>.
    /// </summary>
    [SkippableFact]
    public async Task CarryForward_RespectsTheHorizon_SoADecadeOldAnchorInsertsABoundedNumber()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var anchor = new DateOnly(2015, 1, 1);
        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == anchor ? PublishedQuotes() : []);
        var clock = new MutableTimeProvider(Utc(anchor));
        var job = BuildJob(db, clock, horizonDays: 30, feed);

        await job.RunAsync(CancellationToken.None); // publishes the 2015 anchor

        // Today, nothing published: without a horizon the carry-forward walks
        // from the 2015 anchor to today, a row per gap day for every quote.
        clock.SetUtcNow(Utc(Friday));
        feed.SetHandler((_, _) => []);
        var result = await job.RunAsync(CancellationToken.None);

        // Bounded: at most `horizon x quotes` carried rows, never thousands.
        Assert.True(result.CarriedForward is > 0 and <= 30 * 2,
                    $"expected a bounded 1..60 carried rows, got {result.CarriedForward}");

        var rows = await ReadRatesAsync(db, "EUR");
        // The decade-old anchor is neither deleted nor altered.
        Assert.Contains(rows, r => r.Date == anchor && r.Quote == "USD" && r.Rate == 1.10m
                                   && !r.Deleted && !RateSources.IsCarried(r.Source));
        // No carried row was materialised between the anchor and the horizon.
        var horizonStart = Friday.AddDays(-29);
        Assert.DoesNotContain(rows, r => RateSources.IsCarried(r.Source) && r.Date > anchor && r.Date < horizonStart);
        // A gap day inside the horizon still carries exactly as before.
        Assert.Contains(rows, r => r.Date == Friday && r.Quote == "USD" && r.Rate == 1.10m
                                   && !r.Deleted && RateSources.IsCarried(r.Source));
    }

    /// <summary>
    /// The bounded walk is idempotent: a second pass over the same horizon
    /// inserts nothing and leaves the row set byte-identical, so a pass that
    /// was cut short simply resumes rather than duplicating work.
    /// </summary>
    [SkippableFact]
    public async Task CarryForward_IsIdempotentAcrossBoundedPasses()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        var anchor = new DateOnly(2015, 1, 1);
        var feed = new RecordingRateFeed(RateSources.Ecb);
        feed.SetHandler((date, _) => date == anchor ? PublishedQuotes() : []);
        var clock = new MutableTimeProvider(Utc(anchor));
        var job = BuildJob(db, clock, horizonDays: 30, feed);
        await job.RunAsync(CancellationToken.None);

        clock.SetUtcNow(Utc(Friday));
        feed.SetHandler((_, _) => []);
        var first = await job.RunAsync(CancellationToken.None);
        Assert.True(first.CarriedForward > 0);
        var afterFirst = await ReadRatesAsync(db, "EUR");

        var second = await job.RunAsync(CancellationToken.None);
        var afterSecond = await ReadRatesAsync(db, "EUR");

        Assert.Equal(0, second.CarriedForward);
        Assert.Equal(afterFirst.Count, afterSecond.Count);
    }

    private async Task<NpgsqlConnection> OpenDatabaseAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static RatesJobService BuildJob(NpgsqlConnection db, TimeProvider clock, params IRateFeed[] feeds)
        => BuildJob(db, clock, new RateOptions { BaseCurrencies = ["EUR"] }, feeds);

    /// <summary>A job whose carry-forward horizon is set explicitly, so a bounded pass is testable without a decade of real rows.</summary>
    private static RatesJobService BuildJob(NpgsqlConnection db, TimeProvider clock, int horizonDays, params IRateFeed[] feeds)
        => BuildJob(db, clock, new RateOptions { BaseCurrencies = ["EUR"], CarryForwardHorizonDays = horizonDays }, feeds);

    private static RatesJobService BuildJob(NpgsqlConnection db, TimeProvider clock, RateOptions options, params IRateFeed[] feeds)
    {
        var repository = new RateRepository(db);
        return new RatesJobService(repository, feeds, Microsoft.Extensions.Options.Options.Create(options),
                                   NullLogger<RatesJobService>.Instance, clock);
    }

    private static IReadOnlyList<RateQuote> PublishedQuotes() => [new RateQuote("USD", 1.10m), new RateQuote("RUB", 90.0m)];

    private static DateTimeOffset Utc(DateOnly day) => new(day.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);

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
