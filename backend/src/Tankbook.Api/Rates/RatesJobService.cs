using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Rates;

/// <summary>One job pass's outcome (counts only - never values, docs/LOGGING.md §3).</summary>
public sealed record RatesJobResult(DateOnly Date, int Published, int CarriedForward, int SourcesFailed);

/// <summary>
/// The daily exchange-rate job (docs/SCHEMA.md "Reference data -> Exchange
/// rates"): fetches today's published quotes from every feed, upserts them
/// append-only, then materialises carry-forward - for every date in the covered
/// range with no live quote, it writes a row dated that day carrying the last
/// published value, with <c>source</c> marking it carried. Idempotent: a second
/// pass changes nothing and duplicates nothing. Invocable directly (L2 tests
/// drive <see cref="RunAsync"/>, never a timer); the clock lives in
/// <see cref="RatesHostedService"/>, which is not registered in test hosts.
/// </summary>
public sealed class RatesJobService
{
    private readonly RateRepository _repository;
    private readonly IReadOnlyList<IRateFeed> _feeds;
    private readonly RateOptions _options;
    private readonly ILogger<RatesJobService> _logger;
    private readonly TimeProvider _time;

    public RatesJobService(
        RateRepository repository,
        IEnumerable<IRateFeed> feeds,
        IOptions<RateOptions> options,
        ILogger<RatesJobService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _feeds = feeds.ToArray();
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    public async Task<RatesJobResult> RunAsync(CancellationToken cancellationToken)
    {
        var today = DateOnly.FromDateTime(_time.GetUtcNow().UtcDateTime);
        var publishedSources = _feeds.Select(f => f.Source).ToHashSet(StringComparer.Ordinal);

        var published = 0;
        var sourcesFailed = 0;

        foreach (var baseCurrency in _options.BaseCurrencies)
        {
            foreach (var feed in _feeds)
            {
                IReadOnlyList<RateQuote> quotes;
                try
                {
                    quotes = await feed.FetchAsync(today, baseCurrency, cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // One feed down must not stop the other (docs/SYNC.md offline
                    // behaviour). The pass carries forward from whatever published
                    // values already exist.
                    sourcesFailed++;
                    _logger.LogWarning(ex, "Rate feed {Source} failed for {Date} / {Base}.", feed.Source, today, baseCurrency);
                    continue;
                }

                foreach (var quote in quotes)
                {
                    published += await _repository.UpsertAsync(
                        new RateInsert(today, baseCurrency, quote.Quote, quote.Rate, feed.Source),
                        cancellationToken);
                }
            }
        }

        var carriedForward = 0;
        foreach (var baseCurrency in _options.BaseCurrencies)
        {
            carriedForward += await CarryForwardAsync(baseCurrency, today, publishedSources, cancellationToken);
        }

        if (published > 0 || carriedForward > 0)
        {
            TankbookLog.RatesFetch(_logger, today.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), published, carriedForward, sourcesFailed);
        }

        return new RatesJobResult(today, published, carriedForward, sourcesFailed);
    }

    /// <summary>
    /// Fills every date in the covered range that has no live row for a given
    /// (base, quote) with a carried-forward row dated that day, holding the most
    /// recent published value. A date that already carries any row (live or
    /// soft-deleted) is left alone - a soft-deleted day awaits its correction
    /// re-fetch rather than being silently refilled.
    /// </summary>
    private async Task<int> CarryForwardAsync(string baseCurrency, DateOnly today, IReadOnlySet<string> publishedSources, CancellationToken cancellationToken)
    {
        var rows = await _repository.GetAllForBaseAsync(baseCurrency, cancellationToken);
        var inserted = 0;

        foreach (var group in rows.GroupBy(r => r.Quote, StringComparer.Ordinal))
        {
            var quote = group.Key;
            var published = group
                .Where(r => !r.Deleted && publishedSources.Contains(r.Source))
                .OrderBy(r => r.Date)
                .ToList();

            if (published.Count == 0)
            {
                continue;
            }

            var existingDates = group.Select(r => r.Date).ToHashSet();
            var lastRate = published[0].Rate;
            var lastSource = published[0].Source;
            var index = 0;

            for (var day = published[0].Date; day <= today; day = day.AddDays(1))
            {
                if (index < published.Count && published[index].Date == day)
                {
                    lastRate = published[index].Rate;
                    lastSource = published[index].Source;
                    index++;
                }
                else if (existingDates.Contains(day))
                {
                    // A row already occupies this day (live carried, or
                    // soft-deleted awaiting a correction) - leave it untouched.
                }
                else
                {
                    inserted += await _repository.UpsertAsync(
                        new RateInsert(day, baseCurrency, quote, lastRate, RateSources.Carried(lastSource)),
                        cancellationToken);
                }
            }
        }

        return inserted;
    }
}
