using System.Globalization;
using System.Xml.Linq;

namespace Tankbook.Api.Rates;

/// <summary>
/// The CIS reference-rate feed for the currencies ECB left out (RUB/KZT/AMD/GEL/
/// BYN - docs/SCHEMA.md "Reference data -> Exchange rates"). The real CBR daily
/// XML is RUB-based and only yields the EUR->RUB row directly; the remaining CIS
/// currencies need a commercial EUR-based feed in a production deployment, which
/// is exactly why this sits behind <see cref="IRateFeed"/> and is never exercised
/// by the suite (docs/TESTING.md). This implementation parses the CBR shape and
/// returns the one quote it can express honestly in the requested base.
/// </summary>
public sealed class CisRateFeed : IRateFeed
{
    private const string DailyUrl = "https://www.cbr.ru/scripts/XML_daily.asp";

    private readonly IHttpClientFactory _httpClientFactory;

    public CisRateFeed(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    public string Source => RateSources.Cis;

    public async Task<IReadOnlyList<RateQuote>> FetchAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
    {
        if (!baseCurrency.Equals("EUR", StringComparison.Ordinal))
        {
            return [];
        }

        var client = _httpClientFactory.CreateClient();
        using var response = await client.GetAsync(DailyUrl, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var document = await XDocument.LoadAsync(stream, LoadOptions.None, cancellationToken);

        var root = document.Root;
        if (root is null || root.Name.LocalName != "ValCurs")
        {
            return [];
        }

        var dateAttribute = root.Attribute("Date");
        if (dateAttribute is null ||
            !DateOnly.TryParseExact(dateAttribute.Value, "dd.MM.yyyy", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fileDate) ||
            fileDate != date)
        {
            return [];
        }

        // The EUR Valute row states RUB per 1 EUR, which is the EUR-base quote the
        // schema wants (original-per-home). Other CIS currencies are RUB-based in
        // this feed and would need cross-rates; a production feed serves them
        // directly in EUR base, which is a feed swap, not a code change.
        var eur = root.Elements()
            .FirstOrDefault(e => e.Name.LocalName == "Valute" &&
                                 e.Elements().Any(c => c.Name.LocalName == "CharCode" && c.Value == "EUR"));

        var value = eur?.Elements().FirstOrDefault(c => c.Name.LocalName == "Value")?.Value;
        if (value is null ||
            !decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out var rubPerEur))
        {
            return [];
        }

        return [new RateQuote("RUB", rubPerEur)];
    }
}
