using System.Globalization;
using System.Xml.Linq;

namespace Tankbook.Api.Rates;

/// <summary>
/// The ECB reference-rate feed (docs/SCHEMA.md "Reference data -> Exchange
/// rates"). Fetches the daily eurofxref XML and parses its EUR-based quotes. ECB
/// publishes EUR base only, so a non-EUR base is answered empty. The daily file
/// carries a single date, so a re-fetch for a past date that no longer matches
/// the file answers empty - the daily job only ever asks for today, and past-date
/// corrections use a feed that serves that date. This implementation sits behind
/// <see cref="IRateFeed"/> and is never exercised by the suite (docs/TESTING.md).
/// </summary>
public sealed class EcbRateFeed : IRateFeed
{
    private const string DailyUrl = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml";

    private readonly IHttpClientFactory _httpClientFactory;

    public EcbRateFeed(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    public string Source => RateSources.Ecb;

    public async Task<IReadOnlyList<RateQuote>> FetchAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
    {
        if (!baseCurrency.Equals("EUR", StringComparison.Ordinal))
        {
            return [];
        }

        var client = _httpClientFactory.CreateClient("rates");
        using var response = await client.GetAsync(DailyUrl, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var document = await XDocument.LoadAsync(stream, LoadOptions.None, cancellationToken);

        // Namespace-agnostic: the Cube carrying the time attribute is the day's
        // rate set, regardless of the document's declared namespace prefixes.
        var day = document.Descendants().FirstOrDefault(e =>
            e.Name.LocalName == "Cube" && e.Attribute("time") is not null);
        if (day is null ||
            !DateOnly.TryParse(day.Attribute("time")!.Value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var fileDate) ||
            fileDate != date)
        {
            return [];
        }

        var quotes = new List<RateQuote>();
        foreach (var cube in day.Elements())
        {
            var currency = cube.Attribute("currency")?.Value;
            var rate = cube.Attribute("rate")?.Value;
            if (currency is null ||
                rate is null ||
                !decimal.TryParse(rate, NumberStyles.Number, CultureInfo.InvariantCulture, out var value))
            {
                continue;
            }

            quotes.Add(new RateQuote(currency, value));
        }

        return quotes;
    }
}
