using System.Globalization;
using System.Text;
using System.Xml.Linq;

namespace Tankbook.Api.Rates;

/// <summary>
/// The CIS reference-rate feed (docs/SCHEMA.md "Reference data -> Exchange
/// rates"). The CBR daily XML is RUB-based: it states RUB per <c>Nominal</c>
/// units of every currency it lists, including EUR. That is enough to express
/// the CIS currencies in EUR base without a second network call, because the
/// cross-rate through RUB is arithmetic on one document:
/// <code>quotePerEur = rubPerEur / (value / nominal)</code>
///
/// RV.19 (2026-09-03): the previous comment here claimed the other CIS
/// currencies "would need cross-rates; a production feed serves them directly".
/// The document already carries all of them - AMD, GEL, BYN and KZT - so four of
/// the five currencies this feed exists for were being parsed and thrown away.
///
/// <b>KZT is deliberately NOT served here</b>, even though the document carries
/// it. See <see cref="NbkRateFeed"/>: the National Bank of Kazakhstan's own
/// official rate and this cross-rate disagree by ~0.8% (526.99 vs 531.34 KZT/EUR
/// on 2026-09-03), and NBK is the authoritative publisher for the currency. If
/// both feeds emitted KZT, whichever one the daily job happened to reach first
/// would take the (date, base, quote) slot - the insert is append-only - so the
/// stored series would silently alternate between two sources 0.8% apart and
/// show 0.8% jumps that never happened. One currency, one publisher.
/// </summary>
public sealed class CisRateFeed : IRateFeed
{
    private const string DailyUrl = "https://www.cbr.ru/scripts/XML_daily.asp";

    /// <summary>
    /// The CIS currencies this feed derives by cross-rate through RUB. KZT is
    /// absent on purpose - <see cref="NbkRateFeed"/> owns it (RV.19).
    /// </summary>
    private static readonly string[] CrossRatedCurrencies = ["AMD", "GEL", "BYN"];

    /// <summary>
    /// exchange_rates.rate is numeric(18,8) (docs/SCHEMA.md), so a cross-rate is
    /// rounded to the precision the column actually stores rather than carrying
    /// decimal's full 28 digits into a value that cannot hold them.
    /// </summary>
    private const int RateScale = 8;

    /// <summary>
    /// CBR writes its Value as <c>100,8287</c> - a Russian decimal COMMA. Parsed
    /// with <c>NumberStyles.Number</c> against the invariant culture, that comma
    /// is read as a GROUP separator and 100,8287 becomes 1008287: the rate is
    /// 10,000x too large and still parses, still positive, still plausible to any
    /// assertion that only checks the sign. Found by RV.19's pinned cross-rate
    /// test; it had never reached the database because RV.15 (the windows-1251
    /// bug, fixed the same day) meant the feed had never once succeeded.
    ///
    /// Only a decimal point is allowed, so a grouped number is refused rather
    /// than silently reinterpreted.
    /// </summary>
    private static readonly NumberFormatInfo CbrNumberFormat = new() { NumberDecimalSeparator = "," };

    private const NumberStyles CbrNumberStyles =
        NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite | NumberStyles.AllowDecimalPoint;

    /// <summary>
    /// RV.15: cbr.ru serves the daily rates as **windows-1251**, and says so in
    /// its own XML declaration. .NET Core dropped the legacy codepages from the
    /// default encoding set, so `XDocument` cannot resolve that name and throws
    /// `XmlException` before reading a single rate.
    ///
    /// Measured in production: `SourcesFailed=1` on EVERY pass since the feed
    /// was added - the source had never once succeeded, and the other 23 covered
    /// for it, so the only symptom was a Warning that fired every time and that
    /// nobody read any more.
    ///
    /// Registered here rather than in Program.cs on purpose: this feed is the
    /// only thing in the app that needs a legacy codepage, and a registration
    /// that lives at startup is one a test constructing `CisRateFeed` directly
    /// does not get - which is exactly how this would come back.
    /// `RegisterProvider` is idempotent, so the static constructor running once
    /// per process is the whole cost.
    /// </summary>
    static CisRateFeed()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

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

        // RV.20: ask for the date we were handed. Without date_req CBR serves its
        // default (today's) document and every past-date request was answered
        // empty by the guard below - latent only because the daily job never asks
        // for anything but today, and hard rule 3 makes rateDate the ENTRY date.
        var url = $"{DailyUrl}?date_req={date.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture)}";

        var client = _httpClientFactory.CreateClient("rates");
        using var response = await client.GetAsync(url, cancellationToken);
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
            fileDate > date)
        {
            // RV.20, the decision: a document dated EARLIER than the request is
            // that day's rate, not a failure. CBR does not publish on weekends
            // and holidays, and the rate it last set stays in force until the
            // next one - asking for 04.01 returns the 31.12 document because
            // 31.12's rate IS 04.01's rate. Taking it gives a backfill the right
            // number even when the database has no neighbouring row to carry
            // forward from. A document dated LATER than the request is a
            // different failure - the feed ignoring date_req - and is refused.
            return [];
        }

        var byCode = new Dictionary<string, decimal>(StringComparer.Ordinal);
        foreach (var valute in root.Elements().Where(e => e.Name.LocalName == "Valute"))
        {
            var code = valute.Elements().FirstOrDefault(c => c.Name.LocalName == "CharCode")?.Value;
            var nominalText = valute.Elements().FirstOrDefault(c => c.Name.LocalName == "Nominal")?.Value;
            var valueText = valute.Elements().FirstOrDefault(c => c.Name.LocalName == "Value")?.Value;

            if (code is null || nominalText is null || valueText is null ||
                !int.TryParse(nominalText, NumberStyles.Integer, CultureInfo.InvariantCulture, out var nominal) ||
                nominal <= 0 ||
                !decimal.TryParse(valueText, CbrNumberStyles, CbrNumberFormat, out var value) ||
                value <= 0)
            {
                continue;
            }

            // RUB per ONE unit, nominal folded away.
            byCode[code] = value / nominal;
        }

        if (!byCode.TryGetValue("EUR", out var rubPerEur) || rubPerEur <= 0)
        {
            return [];
        }

        // The EUR row states RUB per 1 EUR, which is already the EUR-base quote
        // the schema wants (original-per-home).
        var quotes = new List<RateQuote> { new("RUB", rubPerEur) };

        foreach (var code in CrossRatedCurrencies)
        {
            if (byCode.TryGetValue(code, out var rubPerUnit) && rubPerUnit > 0)
            {
                quotes.Add(new RateQuote(code, Math.Round(rubPerEur / rubPerUnit, RateScale, MidpointRounding.AwayFromZero)));
            }
        }

        return quotes;
    }
}
