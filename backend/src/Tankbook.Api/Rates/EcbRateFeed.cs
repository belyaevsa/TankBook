using System.Globalization;
using System.Xml.Linq;

namespace Tankbook.Api.Rates;

/// <summary>
/// The ECB reference-rate feed (docs/SCHEMA.md "Reference data -> Exchange
/// rates"). ECB publishes EUR base only, so a non-EUR base is answered empty.
///
/// ECB offers no per-date query; it publishes three static files instead:
/// <c>eurofxref-daily.xml</c> (the newest published day),
/// <c>eurofxref-hist-90d.xml</c> (the last ~90 calendar days of published days)
/// and <c>eurofxref-hist.xml</c> (every published day since 1999). The feed
/// picks the file by how far back the requested date is (RV.135, 2026-09-08):
/// <b>today</b> from the daily file - the only date the daily job asks, and
/// fetched fresh every call so a late-afternoon ECB publish is never missed;
/// a date within <see cref="RecentWindowDays"/> of today from the 90-day file -
/// the common case, a recent import; anything older from the full history - the
/// rare case, a multi-year import.
///
/// The date guard (RV.20, kept in this shape by RV.135) is: a request is
/// answered only from a row whose own <c>time</c> attribute equals the requested
/// date. A date with no row in the file - a weekend or holiday, or a day ECB
/// never published - answers empty, and the backfill either carries a nearby
/// published rate forward or leaves the date absent. Nothing here ever serves
/// today's value for another date: that would put a wrong rate into someone's
/// cost history (hard rule 3), which is worse than the absence RV.135 fixes.
///
/// The two history files are cached on the instance (a feed is a singleton, and
/// the backfill pass asks its dates oldest-first through this same instance), so
/// one pass over N dates makes one upstream request per file it touches, never N
/// - an 8 MB full-history download must not happen per date. The cache is safe
/// for a different reason per edge: a row can only ever appear at the NEWEST end
/// of a file, and <see cref="RecentWindowDays"/> keeps every date routed to the
/// rolling 90-day file inside that file's span, so a snapshot answers a date
/// correctly whenever that date is not newer than the snapshot's newest row - and
/// a request naming a newer day refetches, which is exactly when a stale file
/// would otherwise answer a fillable date empty. A date older than the 90-day
/// file's window is routed to the full history, whose window never rolls.
/// </summary>
public sealed class EcbRateFeed : IRateFeed
{
    private const string DailyUrl = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml";
    private const string RecentUrl = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml";
    private const string FullUrl = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml";

    /// <summary>
    /// How far back a date may be and still be served from the 90-day file. The
    /// file covers ~90 calendar days ending at its newest published day, which
    /// can lag the request across a holiday stretch; 60 keeps a routed date
    /// safely inside the file, so the boundary can never answer a fillable date
    /// empty. Older dates take the full history - one larger download, never a
    /// wrong answer.
    /// </summary>
    private const int RecentWindowDays = 60;

    /// <summary>A parsed history file: its rows by publish day, and its newest day - the cache-freshness key.</summary>
    private sealed record HistoryFile(DateOnly Newest, IReadOnlyDictionary<DateOnly, IReadOnlyList<RateQuote>> Rows);

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly TimeProvider _time;

    // ECB only appends at the newest end of these files, so a snapshot stays
    // valid for every date up to the newest it holds; a request for a newer day
    // refetches. One gate guards both - the daily job and the backfill are
    // separate hosted services and can reach this singleton concurrently.
    private readonly object _cacheGate = new();
    private HistoryFile? _recentCache;
    private HistoryFile? _fullCache;

    public EcbRateFeed(IHttpClientFactory httpClientFactory, TimeProvider time)
    {
        _httpClientFactory = httpClientFactory;
        _time = time;
    }

    public string Source => RateSources.Ecb;

    /// <summary>
    /// ECB's full history file begins 1999-01-04 (the euro's first published
    /// reference rates); no earlier date can ever be served, so this is the
    /// floor the pack response reports for EUR (RV.158). ECB publishes no other
    /// base, so a non-EUR base states no floor.
    /// </summary>
    public DateOnly? CoverageFloor(string baseCurrency)
        => baseCurrency.Equals("EUR", StringComparison.Ordinal) ? new DateOnly(1999, 1, 4) : null;

    public async Task<IReadOnlyList<RateQuote>> FetchAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
    {
        if (!baseCurrency.Equals("EUR", StringComparison.Ordinal))
        {
            return [];
        }

        var today = DateOnly.FromDateTime(_time.GetUtcNow().UtcDateTime);
        if (date >= today)
        {
            return await FetchDailyAsync(date, cancellationToken);
        }

        var daysBack = today.DayNumber - date.DayNumber;
        var url = daysBack <= RecentWindowDays ? RecentUrl : FullUrl;
        return await FetchHistoryAsync(url, date, cancellationToken);
    }

    /// <summary>
    /// The daily file carries a single published day, fetched fresh - the daily
    /// job depends on catching the day's row as soon as ECB publishes it, so this
    /// path is never cached.
    /// </summary>
    private async Task<IReadOnlyList<RateQuote>> FetchDailyAsync(DateOnly date, CancellationToken cancellationToken)
    {
        var document = await LoadDocumentAsync(DailyUrl, cancellationToken);
        return QuotesFor(document, date) ?? [];
    }

    private async Task<IReadOnlyList<RateQuote>> FetchHistoryAsync(string url, DateOnly date, CancellationToken cancellationToken)
    {
        lock (_cacheGate)
        {
            var cached = url == RecentUrl ? _recentCache : _fullCache;
            if (cached is not null && date <= cached.Newest)
            {
                return cached.Rows.TryGetValue(date, out var quotes) ? quotes : [];
            }
        }

        var fresh = ParseHistory(await LoadDocumentAsync(url, cancellationToken));

        lock (_cacheGate)
        {
            // A concurrent caller may have stored a newer snapshot while this
            // one fetched; keep the newer so the gate stays correct.
            var current = url == RecentUrl ? _recentCache : _fullCache;
            if (current is null || fresh.Newest > current.Newest)
            {
                if (url == RecentUrl)
                {
                    _recentCache = fresh;
                }
                else
                {
                    _fullCache = fresh;
                }
            }

            var winner = (url == RecentUrl ? _recentCache : _fullCache)!;
            return winner.Rows.TryGetValue(date, out var quotes) ? quotes : [];
        }
    }

    private async Task<XDocument> LoadDocumentAsync(string url, CancellationToken cancellationToken)
    {
        var client = _httpClientFactory.CreateClient("rates");
        using var response = await client.GetAsync(url, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await XDocument.LoadAsync(stream, LoadOptions.None, cancellationToken);
    }

    /// <summary>
    /// Parses every published day out of a history file. Namespace-agnostic: the
    /// Cube carrying the time attribute is one published day's rate set.
    /// </summary>
    private static HistoryFile ParseHistory(XDocument document)
    {
        var rows = new Dictionary<DateOnly, IReadOnlyList<RateQuote>>();
        foreach (var day in DayCubes(document))
        {
            var date = day.Item1;
            var quotes = day.Item2;
            if (rows.TryGetValue(date, out var existing))
            {
                // A repeated day in a recaptured file keeps the first row - the
                // same day's rate must not vary within one document.
                continue;
            }

            rows[date] = quotes;
        }

        return new HistoryFile(rows.Keys.DefaultIfEmpty().Max(), rows);
    }

    /// <summary>
    /// The quotes a document published for one requested date, or null when the
    /// document carries no row dated that day. The single date guard (RV.20,
    /// RV.135): whether the file is today's or a history file, only that date's
    /// own row may answer it.
    /// </summary>
    private static IReadOnlyList<RateQuote>? QuotesFor(XDocument document, DateOnly date)
    {
        foreach (var (day, quotes) in DayCubes(document))
        {
            if (day == date)
            {
                return quotes;
            }
        }

        return null;
    }

    /// <summary>Enumerates the document's published days, newest row first as ECB writes them.</summary>
    private static IEnumerable<(DateOnly Date, IReadOnlyList<RateQuote> Quotes)> DayCubes(XDocument document)
    {
        foreach (var cube in document.Descendants().Where(e =>
                     e.Name.LocalName == "Cube" && e.Attribute("time") is not null))
        {
            if (!DateOnly.TryParse(cube.Attribute("time")!.Value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
            {
                continue;
            }

            var quotes = new List<RateQuote>();
            foreach (var rate in cube.Elements())
            {
                var currency = rate.Attribute("currency")?.Value;
                var value = rate.Attribute("rate")?.Value;
                if (currency is null ||
                    value is null ||
                    !decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed))
                {
                    continue;
                }

                quotes.Add(new RateQuote(currency, parsed));
            }

            yield return (date, quotes);
        }
    }
}
