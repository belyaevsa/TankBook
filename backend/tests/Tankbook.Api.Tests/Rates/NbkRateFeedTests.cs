using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests;

/// <summary>
/// RV.19: KZT comes from the National Bank of Kazakhstan, not from a CBR
/// cross-rate through Moscow. Against the REAL nationalbank.kz responses
/// captured on 2026-09-03.
/// </summary>
public class NbkRateFeedTests
{
    private const string TodayFixture = "nbk-rates-2026-09-03.xml";
    private const string PastFixture = "nbk-rates-2026-08-15.xml";

    private static readonly DateOnly Today = new(2026, 9, 3);
    private static readonly DateOnly PastDate = new(2026, 8, 15);

    private static (NbkRateFeed Feed, FixtureRoutingHandler Handler) FeedServingNbk()
    {
        var handler = new FixtureRoutingHandler(TodayFixture, ("fdate=15.08.2026", PastFixture));
        var services = new ServiceCollection();
        services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => handler);
        var feed = new NbkRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>());
        return (feed, handler);
    }

    /// <summary>
    /// The fixture is the evidence, so it is asserted. NBK serves UTF-8 - one of
    /// the reasons it is the better feed mechanically (no windows-1251 trap,
    /// RV.15) - and this pins that a recapture has not changed the wire shape the
    /// parser depends on.
    /// </summary>
    [Theory]
    [InlineData(TodayFixture)]
    [InlineData(PastFixture)]
    public void TheCapturedNbkFixtureIsUtf8AndCarriesTheRssShape(string fixture)
    {
        var bytes = RateFeedFixtures.Bytes(fixture);
        var head = Encoding.ASCII.GetString(bytes, 0, 60);
        Assert.Contains("encoding=\"utf-8\"", head, StringComparison.Ordinal);

        var body = Encoding.UTF8.GetString(bytes);
        Assert.Contains("<title>EUR</title>", body, StringComparison.Ordinal);
        Assert.Contains("<quant>", body, StringComparison.Ordinal);
    }

    /// <summary>The date must reach the wire, in NBK's dd.MM.yyyy form.</summary>
    [Fact]
    public async Task TheFeedAsksNbkForTheDateItWasHanded()
    {
        var (feed, handler) = FeedServingNbk();

        await feed.FetchAsync(PastDate, "EUR", CancellationToken.None);

        var request = Assert.Single(handler.Requests);
        Assert.Contains("fdate=15.08.2026", request.Query, StringComparison.Ordinal);
    }

    /// <summary>
    /// The reason the feed exists: NBK's official EUR quote for 2026-09-03 is
    /// 526.99 KZT, read directly off the document with no cross-rate.
    /// </summary>
    [Fact]
    public async Task TheEurQuoteIsTheOfficialKztRateFromTheDocument()
    {
        var (feed, _) = FeedServingNbk();

        var quotes = await feed.FetchAsync(Today, "EUR", CancellationToken.None);

        var kzt = Assert.Single(quotes);
        Assert.Equal("KZT", kzt.Quote);
        Assert.Equal(526.99m, kzt.Rate);
    }

    /// <summary>
    /// The whole justification for a second feed, asserted rather than asserted
    /// about: NBK's own rate and the CBR cross-rate through RUB for the SAME day
    /// are 0.8% apart - about 40 KZT on a 4800 KZT fill. If these two ever
    /// converged this test would go red and the second feed could be retired.
    /// </summary>
    [Fact]
    public async Task TheOfficialNbkRateDiffersMateriallyFromTheCbrCrossRate()
    {
        var (feed, _) = FeedServingNbk();

        var quotes = await feed.FetchAsync(Today, "EUR", CancellationToken.None);

        var nbk = Assert.Single(quotes).Rate;
        var cbr = CisRateFeedCrossRateTests.CbrKztCrossRateOn20260903;
        Assert.NotEqual(cbr, nbk);

        var spreadPercent = Math.Abs(cbr - nbk) / nbk * 100m;
        Assert.InRange(spreadPercent, 0.5m, 2.0m);
    }

    /// <summary>A past date returns that day's quote: 536.18 KZT per EUR on 15.08.2026.</summary>
    [Fact]
    public async Task APastDateReturnsThatDaysQuote()
    {
        var (feed, _) = FeedServingNbk();

        var quotes = await feed.FetchAsync(PastDate, "EUR", CancellationToken.None);

        Assert.Equal(536.18m, Assert.Single(quotes).Rate);
    }

    /// <summary>
    /// quant is READ, never assumed. AMD is the proof from a real document: NBK
    /// quotes it per 10 units (12.56 KZT per 10 AMD), so the per-unit rate is
    /// 1.256. A parser that ignored quant would return 12.56 and be wrong by 10x.
    /// </summary>
    [Fact]
    public async Task TheQuantDivisorIsReadFromTheDocument()
    {
        var (feed, _) = FeedServingNbk();

        var quotes = await feed.FetchAsync(Today, "AMD", CancellationToken.None);

        Assert.Equal(1.256m, Assert.Single(quotes).Rate);
    }

    /// <summary>
    /// Same rule as CisRateFeed (RV.20): a document dated after the request means
    /// the endpoint ignored fdate, which is a failure and not a rate.
    /// </summary>
    [Fact]
    public async Task ADocumentDatedAfterTheRequestIsRefused()
    {
        var services = new ServiceCollection();
        services.AddHttpClient("rates")
            .ConfigurePrimaryHttpMessageHandler(() => new FixtureRoutingHandler(TodayFixture));
        var feed = new NbkRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>());

        var quotes = await feed.FetchAsync(PastDate, "EUR", CancellationToken.None);

        Assert.Empty(quotes);
    }

    /// <summary>A base NBK does not list is answered empty, like every other feed.</summary>
    [Fact]
    public async Task ABaseTheDocumentDoesNotListIsAnsweredEmpty()
    {
        var (feed, _) = FeedServingNbk();

        var quotes = await feed.FetchAsync(Today, "XXX", CancellationToken.None);

        Assert.Empty(quotes);
    }
}
