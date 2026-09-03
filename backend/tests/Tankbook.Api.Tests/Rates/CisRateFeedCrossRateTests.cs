using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests;

/// <summary>
/// RV.19 + RV.20, against the REAL cbr.ru responses captured on 2026-09-03.
///
/// RV.19: the feed parsed a document carrying five CIS currencies and returned
/// one of them. RV.20: it fetched the DEFAULT document whatever date it was
/// handed, then discarded it unless the document's own date matched - so every
/// past-date request was answered empty, and every weekend the last published
/// document was thrown away.
///
/// The expected cross-rates below are HAND-COMPUTED from the fixture's own
/// Nominal/Value pairs, written out as literals. They are deliberately not
/// recomputed in the assertion: an assertion that redoes the division passes
/// against any division, including a wrong one.
/// </summary>
public class CisRateFeedCrossRateTests
{
    private const string TodayFixture = "cbr-xml-daily-windows1251.xml";
    private const string PastFixture = "cbr-xml-daily-2026-08-15-windows1251.xml";
    private const string HolidayFixture = "cbr-xml-daily-2026-01-04-holiday-windows1251.xml";

    private static readonly DateOnly Today = new(2026, 9, 3);
    private static readonly DateOnly PastDate = new(2026, 8, 15);
    private static readonly DateOnly NewYearHoliday = new(2026, 1, 4);

    /// <summary>
    /// The cross-rate the CBR document yields for KZT on 2026-09-03, hand-computed:
    /// 100.8287 RUB/EUR / (18.9762 RUB / 100 KZT) = 531.34294537 KZT/EUR.
    /// NBK's own official rate for the same day is 526.99 - see NbkRateFeedTests.
    /// </summary>
    public const decimal CbrKztCrossRateOn20260903 = 531.34294537m;

    private static (CisRateFeed Feed, FixtureRoutingHandler Handler) FeedServingCbr()
    {
        var handler = new FixtureRoutingHandler(
            TodayFixture,
            ("date_req=15/08/2026", PastFixture),
            ("date_req=04/01/2026", HolidayFixture));

        var services = new ServiceCollection();
        services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => handler);
        var feed = new CisRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>());
        return (feed, handler);
    }

    /// <summary>
    /// Every CBR fixture must still be windows-1251 bytes. A recapture saved as
    /// UTF-8 would silently remove the RV.15 regression coverage while leaving
    /// every test in this file green.
    /// </summary>
    [Theory]
    [InlineData(TodayFixture)]
    [InlineData(PastFixture)]
    [InlineData(HolidayFixture)]
    public void EveryCapturedCbrFixtureIsActuallyWindows1251(string fixture)
    {
        var head = Encoding.ASCII.GetString(RateFeedFixtures.Bytes(fixture), 0, 60);
        Assert.Contains("encoding=\"windows-1251\"", head, StringComparison.Ordinal);
    }

    /// <summary>RV.20: the date must reach the wire, in CBR's dd/MM/yyyy form.</summary>
    [Fact]
    public async Task TheFeedAsksCbrForTheDateItWasHanded()
    {
        var (feed, handler) = FeedServingCbr();

        await feed.FetchAsync(PastDate, "EUR", CancellationToken.None);

        var request = Assert.Single(handler.Requests);
        Assert.Contains("date_req=15/08/2026", request.Query, StringComparison.Ordinal);
    }

    /// <summary>
    /// RV.19: all four currencies this feed serves, pinned to the 2026-09-03
    /// document. RUB is read straight off the EUR row (100.8287 RUB per 1 EUR);
    /// the rest are rubPerEur / (Value / Nominal), computed by hand:
    ///   AMD: 100.8287 / (23.8909 / 100) = 422.03809819
    ///   GEL: 100.8287 / (33.1414 / 1)   =   3.04237902
    ///   BYN: 100.8287 / (28.3496 / 1)   =   3.55661808
    /// </summary>
    [Fact]
    public async Task TheCrossRatesArePinnedToTheCapturedDocument()
    {
        var (feed, _) = FeedServingCbr();

        var quotes = await feed.FetchAsync(Today, "EUR", CancellationToken.None);

        Assert.Equal(100.8287m, Assert.Single(quotes, q => q.Quote == "RUB").Rate);
        Assert.Equal(422.03809819m, Assert.Single(quotes, q => q.Quote == "AMD").Rate);
        Assert.Equal(3.04237902m, Assert.Single(quotes, q => q.Quote == "GEL").Rate);
        Assert.Equal(3.55661808m, Assert.Single(quotes, q => q.Quote == "BYN").Rate);
    }

    /// <summary>
    /// The decimal COMMA, found while pinning the cross-rates (RV.19). CBR writes
    /// 100,8287 and the parser read it against the invariant culture, where a
    /// comma is a GROUP separator: the rate came out as 1008287 - 10,000x too
    /// large, positive, and invisible to any assertion that only checks the sign.
    /// It never reached the database only because the feed had never once parsed
    /// (RV.15, the windows-1251 bug fixed the same day). This asserts the
    /// magnitude, which is the part that was wrong.
    /// </summary>
    [Fact]
    public async Task TheRussianDecimalCommaIsNotReadAsAThousandsSeparator()
    {
        var (feed, _) = FeedServingCbr();

        var quotes = await feed.FetchAsync(Today, "EUR", CancellationToken.None);

        // A euro is worth ~100 roubles, not ~1,000,000.
        Assert.InRange(Assert.Single(quotes, q => q.Quote == "RUB").Rate, 10m, 1000m);
    }

    /// <summary>
    /// RV.19, the decision: KZT is in this document and is deliberately NOT
    /// served here - NbkRateFeed owns it, because the cross-rate and the National
    /// Bank of Kazakhstan's own rate disagree by 0.8%. Two feeds writing the same
    /// (date, base, quote) slot would be settled by whichever ran first.
    /// </summary>
    [Fact]
    public async Task KztIsLeftToTheNationalBankOfKazakhstan()
    {
        var (feed, _) = FeedServingCbr();

        var quotes = await feed.FetchAsync(Today, "EUR", CancellationToken.None);

        Assert.DoesNotContain(quotes, q => q.Quote == "KZT");
    }

    /// <summary>
    /// RV.20: a past date returns THAT day's quotes. Before the fix this was an
    /// empty list - the feed fetched today's document and the date guard binned
    /// it. Hand-computed from the 15.08.2026 document (97.5141 RUB/EUR):
    ///   AMD: 97.5141 / (23.1111 / 100) = 421.93621247
    ///   GEL: 97.5141 / (32.3048 / 1)   =   3.01856380
    ///   BYN: 97.5141 / (28.2702 / 1)   =   3.44936010
    /// </summary>
    [Fact]
    public async Task APastDateReturnsThatDaysQuotes()
    {
        var (feed, _) = FeedServingCbr();

        var quotes = await feed.FetchAsync(PastDate, "EUR", CancellationToken.None);

        Assert.Equal(97.5141m, Assert.Single(quotes, q => q.Quote == "RUB").Rate);
        Assert.Equal(421.93621247m, Assert.Single(quotes, q => q.Quote == "AMD").Rate);
        Assert.Equal(3.01856380m, Assert.Single(quotes, q => q.Quote == "GEL").Rate);
        Assert.Equal(3.44936010m, Assert.Single(quotes, q => q.Quote == "BYN").Rate);
    }

    /// <summary>
    /// RV.20, the weekend/holiday case and the answer this task chose: a document
    /// dated EARLIER than the request is that day's rate, not a failure. CBR
    /// stops publishing over the New Year holidays, so asking for 04.01.2026
    /// returns the document dated 31.12.2025 - and 31.12's rate is the rate in
    /// force on 04.01. Taking it means a backfill gets the right number even when
    /// the database holds no neighbouring row to carry forward from.
    /// Hand-computed from the 31.12.2025 document (92.0938 RUB/EUR):
    ///   AMD: 92.0938 / (20.5126 / 100) = 448.96210134
    /// </summary>
    [Fact]
    public async Task ADocumentDatedEarlierThanTheRequestIsThatDaysRate()
    {
        var (feed, _) = FeedServingCbr();

        var quotes = await feed.FetchAsync(NewYearHoliday, "EUR", CancellationToken.None);

        Assert.Equal(92.0938m, Assert.Single(quotes, q => q.Quote == "RUB").Rate);
        Assert.Equal(448.96210134m, Assert.Single(quotes, q => q.Quote == "AMD").Rate);
    }

    /// <summary>
    /// The other side of that rule: a document dated AFTER the request is the
    /// feed ignoring date_req, which is a failure and not a rate. Simulated by a
    /// handler that serves today's document whatever is asked - exactly what
    /// cbr.ru does when the parameter is missing.
    /// </summary>
    [Fact]
    public async Task ADocumentDatedAfterTheRequestIsRefused()
    {
        var services = new ServiceCollection();
        services.AddHttpClient("rates")
            .ConfigurePrimaryHttpMessageHandler(() => new FixtureRoutingHandler(TodayFixture));
        var feed = new CisRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>());

        var quotes = await feed.FetchAsync(PastDate, "EUR", CancellationToken.None);

        Assert.Empty(quotes);
    }

    /// <summary>A base CBR cannot express in this shape is answered empty, as before.</summary>
    [Fact]
    public async Task ANonEurBaseIsAnsweredEmpty()
    {
        var (feed, _) = FeedServingCbr();

        var quotes = await feed.FetchAsync(Today, "USD", CancellationToken.None);

        Assert.Empty(quotes);
    }
}
