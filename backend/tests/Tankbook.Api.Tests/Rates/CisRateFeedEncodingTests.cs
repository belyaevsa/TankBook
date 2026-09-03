using System.Net;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests;

/// <summary>
/// RV.15: the CIS feed had never once succeeded in production.
///
/// cbr.ru serves its daily rates as **windows-1251** and names that encoding in
/// its own XML declaration. .NET Core dropped the legacy codepages from the
/// default encoding set, so <c>XDocument</c> could not resolve the name and
/// threw <c>XmlException</c> before reading a rate. The log said
/// <c>SourcesFailed=1</c> on every pass; the other 23 sources covered the pack,
/// so the only symptom was a Warning that fired every time and that nobody read.
///
/// These run against the REAL response captured on 2026-09-03, bytes intact, so
/// the next change to that feed is visible here rather than in production.
/// </summary>
public class CisRateFeedEncodingTests
{
    private static string FixturePath =>
        Path.Combine(AppContext.BaseDirectory, "Rates", "Fixtures", "cbr-xml-daily-windows1251.xml");

    private static CisRateFeed FeedServing(byte[] body)
    {
        var services = new ServiceCollection();
        services.AddHttpClient("rates")
            .ConfigurePrimaryHttpMessageHandler(() => new StubHandler(body));
        return new CisRateFeed(services.BuildServiceProvider().GetRequiredService<IHttpClientFactory>());
    }

    /// <summary>
    /// The fixture is the evidence, so it is asserted rather than assumed: if a
    /// future capture is saved as UTF-8, these tests would pass while proving
    /// nothing about the bug.
    /// </summary>
    [Fact]
    public void TheCapturedFixtureIsActuallyWindows1251()
    {
        var head = Encoding.ASCII.GetString(File.ReadAllBytes(FixturePath), 0, 60);
        Assert.Contains("encoding=\"windows-1251\"", head, StringComparison.Ordinal);
    }

    /// <summary>
    /// The bug itself: parsing the real bytes must produce real quotes. Before
    /// the CodePages provider was registered this threw XmlException here.
    /// </summary>
    [Fact]
    public async Task TheRealWindows1251FeedParses()
    {
        var feed = FeedServing(File.ReadAllBytes(FixturePath));

        var quotes = await feed.FetchAsync(new DateOnly(2026, 9, 3), "EUR", CancellationToken.None);

        // Non-empty AND carrying the currencies this feed exists for - an empty
        // list would also be "no exception", which is what the broken feed's
        // CALLER saw and is not what fixing it means.
        Assert.NotEmpty(quotes);
        Assert.Contains(quotes, q => q.Quote == "RUB");
    }

    /// <summary>
    /// The rate is a NUMBER read from the document, not merely a currency code.
    /// Without this a parser that returned every code at zero would pass above.
    /// </summary>
    [Fact]
    public async Task TheParsedRubQuoteCarriesAPositiveRate()
    {
        var feed = FeedServing(File.ReadAllBytes(FixturePath));

        var quotes = await feed.FetchAsync(new DateOnly(2026, 9, 3), "EUR", CancellationToken.None);

        var rub = Assert.Single(quotes, q => q.Quote == "RUB");
        Assert.True(rub.Rate > 0, $"RUB rate must be positive; got {rub.Rate}");
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly byte[] _body;

        public StubHandler(byte[] body) => _body = body;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(_body),
            });
    }
}
