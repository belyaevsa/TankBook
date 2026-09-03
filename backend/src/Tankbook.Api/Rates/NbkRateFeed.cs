using System.Globalization;
using System.Xml.Linq;

namespace Tankbook.Api.Rates;

/// <summary>
/// The National Bank of Kazakhstan feed - the authoritative publisher of KZT
/// (RV.19, docs/SCHEMA.md "Reference data -> Exchange rates").
///
/// <b>Why a second feed rather than a branch inside <see cref="CisRateFeed"/>.</b>
/// The CBR document carries KZT, so a cross-rate through RUB is available for
/// free - and it is the wrong number. On 2026-09-03 the cross-rate gave
/// 531.34 KZT/EUR while NBK's own official rate was 526.99: <b>0.8% apart</b>,
/// about 40 KZT on a 4800 KZT fill, for a currency Kazakh users actually spend.
/// NBK is also the better feed mechanically: UTF-8 (no windows-1251 trap, RV.15)
/// and a <b>direct</b> EUR quote, so no cross-rate compounds two roundings.
/// Separate feeds also mean a failure in one cannot take the other down -
/// <see cref="RatesJobService"/> counts SourcesFailed per feed.
///
/// <b>One currency, one publisher.</b> This feed publishes KZT and only KZT, and
/// <see cref="CisRateFeed"/> deliberately omits it. Both writing KZT would be
/// decided by whichever feed the job reached first (the insert is append-only,
/// so the first row into a (date, base, quote) slot wins), and the stored series
/// would alternate between two sources 0.8% apart - phantom jumps in a user's
/// own cost history. If NBK is down for a day, KZT is carried forward from NBK's
/// last published value rather than filled with a differently-sourced number.
///
/// <b>The wire shape.</b> <c>get_rates.cfm?fdate=dd.MM.yyyy</c> returns
/// <c>&lt;rates&gt;</c> with a <c>&lt;date&gt;</c> and one <c>&lt;item&gt;</c>
/// per currency: <c>&lt;title&gt;EUR&lt;/title&gt;</c>,
/// <c>&lt;description&gt;526.99&lt;/description&gt;</c>,
/// <c>&lt;quant&gt;1&lt;/quant&gt;</c>. The quote is <b>KZT per quant units</b>
/// of the named currency (AMD is quoted per 10), so <c>quant</c> is read, never
/// assumed.
/// </summary>
public sealed class NbkRateFeed : IRateFeed
{
    private const string RatesUrl = "https://nationalbank.kz/rss/get_rates.cfm";

    /// <summary>exchange_rates.rate is numeric(18,8) (docs/SCHEMA.md).</summary>
    private const int RateScale = 8;

    private readonly IHttpClientFactory _httpClientFactory;

    public NbkRateFeed(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    public string Source => RateSources.Nbk;

    public async Task<IReadOnlyList<RateQuote>> FetchAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
    {
        var client = _httpClientFactory.CreateClient("rates");
        var url = $"{RatesUrl}?fdate={date.ToString("dd.MM.yyyy", CultureInfo.InvariantCulture)}";
        using var response = await client.GetAsync(url, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var document = await XDocument.LoadAsync(stream, LoadOptions.None, cancellationToken);

        var root = document.Root;
        if (root is null || root.Name.LocalName != "rates")
        {
            return [];
        }

        // Same rule as CisRateFeed (RV.20): a document dated earlier than the
        // request is the rate in force that day; one dated later means the
        // endpoint ignored fdate and is refused.
        var dateText = root.Elements().FirstOrDefault(e => e.Name.LocalName == "date")?.Value;
        if (dateText is null ||
            !DateOnly.TryParseExact(dateText.Trim(), "dd.MM.yyyy", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fileDate) ||
            fileDate > date)
        {
            return [];
        }

        // NBK quotes KZT per `quant` units of `title`, so the base currency's own
        // row IS the EUR-base KZT quote once quant is folded away. A base NBK
        // does not list is answered empty, like every other feed.
        foreach (var item in root.Elements().Where(e => e.Name.LocalName == "item"))
        {
            var code = item.Elements().FirstOrDefault(c => c.Name.LocalName == "title")?.Value?.Trim();
            if (code is null || !code.Equals(baseCurrency, StringComparison.Ordinal))
            {
                continue;
            }

            var valueText = item.Elements().FirstOrDefault(c => c.Name.LocalName == "description")?.Value;
            var quantText = item.Elements().FirstOrDefault(c => c.Name.LocalName == "quant")?.Value;

            if (valueText is null ||
                !decimal.TryParse(valueText.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out var kztPerQuant) ||
                kztPerQuant <= 0)
            {
                return [];
            }

            var quant = 1;
            if (quantText is not null &&
                (!int.TryParse(quantText.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out quant) || quant <= 0))
            {
                return [];
            }

            return [new RateQuote("KZT", Math.Round(kztPerQuant / quant, RateScale, MidpointRounding.AwayFromZero))];
        }

        return [];
    }
}
