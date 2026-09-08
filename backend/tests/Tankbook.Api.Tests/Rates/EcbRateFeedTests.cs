using Microsoft.Extensions.DependencyInjection;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// RV.135: the ECB feed must serve EUR dates older than today, or every past EUR
/// demand answers empty forever. Against the REAL ECB eurofxref rows captured
/// 2026-09-08, trimmed to the tested days and served by path (ECB's three files
/// differ by URL, not by query). "Today" is pinned to 2026-08-26 so the daily,
/// the 90-day and the full-history paths are all reachable from one clock.
/// These are L1 - the feed behind a stubbed HttpClient, no Postgres
/// (docs/TESTING.md "mock the boundary").
/// </summary>
public class EcbRateFeedTests
{
    private const string DailyFixture = "ecb-eurofxref-daily-2026-08-26.xml";
    private const string RecentFixture = "ecb-eurofxref-hist-90d-2026-08-26.xml";
    private const string FullFixture = "ecb-eurofxref-hist-2015.xml";

    // Real ECB values for the fixture dates.
    private static readonly DateOnly Today = new(2026, 8, 26);
    private static readonly decimal TodayUsd = 1.1669m;
    private static readonly DateOnly RecentA = new(2026, 8, 25);
    private static readonly DateOnly RecentB = new(2026, 8, 24);
    private static readonly decimal RecentAUsd = 1.1662m;
    private static readonly decimal RecentBUsd = 1.1664m;
    private static readonly DateOnly OldDate = new(2015, 6, 16);
    private static readonly DateOnly OldDateBefore = new(2015, 6, 15);
    private static readonly decimal OldDateUsd = 1.1215m;
    private static readonly decimal OldDateBeforeUsd = 1.1218m;
    private static readonly DateOnly SaturdayInTheArchive = new(2015, 6, 20);

    /// <summary>The real feed behind a path-routing handler serving the three ECB fixture files.</summary>
    private static (EcbRateFeed Feed, PathRoutingHandler Handler) FeedServingAllFiles()
    {
        var handler = new PathRoutingHandler(
        [
            ("eurofxref-daily.xml", DailyFixture),
            ("eurofxref-hist-90d.xml", RecentFixture),
            ("eurofxref-hist.xml", FullFixture),
        ]);
        return (BuildFeed(handler), handler);
    }

    private static EcbRateFeed BuildFeed(PathRoutingHandler handler)
    {
        var services = new ServiceCollection();
        services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => handler);
        var clock = new MutableTimeProvider(new DateTimeOffset(Today.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero));
        return new EcbRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>(), clock);
    }

    [Fact]
    public async Task Today_IsServedFromTheDailyFile()
    {
        var (feed, handler) = FeedServingAllFiles();

        var quotes = await feed.FetchAsync(Today, "EUR", CancellationToken.None);

        Assert.Equal(TodayUsd, Quote(quotes, "USD").Rate);
        var request = Assert.Single(handler.Requests);
        Assert.Contains("eurofxref-daily.xml", request.AbsolutePath, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ARecentDate_IsServedFromThe90DayFile_FromItsOwnRow()
    {
        var (feed, handler) = FeedServingAllFiles();

        var quotes = await feed.FetchAsync(RecentA, "EUR", CancellationToken.None);

        // The fixture holds two days; the value must be the requested day's, not
        // the file's other day's - a feed serving the wrong row fails here.
        Assert.Equal(RecentAUsd, Quote(quotes, "USD").Rate);
        var request = Assert.Single(handler.Requests);
        Assert.Contains("eurofxref-hist-90d.xml", request.AbsolutePath, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnotherRecentDate_IsServedItsOwnRow_NotTheFirstInTheFile()
    {
        var (feed, _) = FeedServingAllFiles();

        var quotes = await feed.FetchAsync(RecentB, "EUR", CancellationToken.None);

        Assert.Equal(RecentBUsd, Quote(quotes, "USD").Rate);
        Assert.NotEqual(RecentAUsd, Quote(quotes, "USD").Rate);
    }

    [Fact]
    public async Task ADecadeOldDate_IsServedFromTheFullHistory_FromItsOwnRow()
    {
        var (feed, handler) = FeedServingAllFiles();

        var quotes = await feed.FetchAsync(OldDate, "EUR", CancellationToken.None);

        Assert.Equal(OldDateUsd, Quote(quotes, "USD").Rate);
        var request = Assert.Single(handler.Requests);
        Assert.Contains("eurofxref-hist.xml", request.AbsolutePath, StringComparison.Ordinal);
    }

    /// <summary>
    /// The fixture carries two adjacent 2015 days with different USD values. Each
    /// requested day must come back with its OWN value - the wrong-row trap a
    /// feed that grabbed the newest day in the file would fall into.
    /// </summary>
    [Fact]
    public async Task EachOldDate_AnswersWithItsOwnDayValue_NotANeighbouringOne()
    {
        var (feed, _) = FeedServingAllFiles();

        var first = await feed.FetchAsync(OldDate, "EUR", CancellationToken.None);
        var second = await feed.FetchAsync(OldDateBefore, "EUR", CancellationToken.None);

        Assert.Equal(OldDateUsd, Quote(first, "USD").Rate);
        Assert.Equal(OldDateBeforeUsd, Quote(second, "USD").Rate);
        Assert.NotEqual(Quote(first, "USD").Rate, Quote(second, "USD").Rate);
    }

    /// <summary>
    /// The date guard survives a WRONG file: even when the only row the server
    /// offers is today's (the handler serves the daily fixture for every path),
    /// a past-date request must answer empty rather than take today's value -
    /// hard rule 3 would otherwise put today's rate into a 2015 cost.
    /// </summary>
    [Fact]
    public async Task APastDate_NeverTakesTodaysRow_EvenWhenThatIsAllTheServerServes()
    {
        // No path routes match: every file request gets the daily fixture.
        var handler = new PathRoutingHandler([], fallbackFixture: DailyFixture);
        var feed = BuildFeed(handler);

        var quotes = await feed.FetchAsync(OldDate, "EUR", CancellationToken.None);

        Assert.Empty(quotes);
        Assert.Single(handler.Requests); // it did ask, and was refused by the row guard
    }

    /// <summary>
    /// A date the history genuinely lacks - a weekend, ECB publishes working days
    /// only - is answered empty, never guessed from a neighbouring day's row.
    /// The carry rule that resolves it lives in the backfill, not in the feed.
    /// </summary>
    [Fact]
    public async Task AWeekendTheHistoryLacks_IsAnsweredEmpty_NeverGuessed()
    {
        var (feed, _) = FeedServingAllFiles();

        var quotes = await feed.FetchAsync(SaturdayInTheArchive, "EUR", CancellationToken.None);

        Assert.Empty(quotes);
    }

    /// <summary>A base ECB does not publish is answered empty without any upstream request.</summary>
    [Fact]
    public async Task ANonEurBase_IsAnsweredEmpty_WithoutAnHttpRequest()
    {
        var (feed, handler) = FeedServingAllFiles();

        var quotes = await feed.FetchAsync(OldDate, "USD", CancellationToken.None);

        Assert.Empty(quotes);
        Assert.Empty(handler.Requests);
    }

    /// <summary>
    /// A feed instance caches the history file, so asking many dates makes one
    /// upstream request, not one per date - the bounded-upstream property the
    /// backfill pass relies on (docs/SCHEMA.md). Two dates + a repeat = one GET.
    /// </summary>
    [Fact]
    public async Task SeveralDatesFromOneFile_CostOneUpstreamRequest()
    {
        var (feed, handler) = FeedServingAllFiles();

        await feed.FetchAsync(RecentA, "EUR", CancellationToken.None);
        await feed.FetchAsync(RecentB, "EUR", CancellationToken.None);
        await feed.FetchAsync(RecentA, "EUR", CancellationToken.None);

        Assert.Single(handler.Requests);
    }

    private static RateQuote Quote(IReadOnlyList<RateQuote> quotes, string currency)
        => Assert.Single(quotes, q => q.Quote == currency);
}
