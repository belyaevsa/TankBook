using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Rates;

/// <summary>One backfill pass's outcome (counts only - never values, docs/LOGGING.md §3).</summary>
public sealed record RateBackfillResult(int Processed, int Published, int CarriedForward, int SourcesFailed);

/// <summary>
/// The demand-driven exchange-rate backfill (docs/SCHEMA.md "Reference data ->
/// Exchange rates"). The daily job fetches only today; hard rule 3 makes
/// <c>rateDate</c> the ENTRY date, so a past date a device needs would never be
/// fetched at all - the RV.32 defect. The trigger is <c>GET /v1/rates/pack</c>:
/// a request for a range is the statement "I need these dates", so
/// <see cref="RecordRequestAsync"/> queues the dates that have no rate, the
/// response returns what exists immediately (never blocking on an upstream
/// fetch - 400 dates x 2 feeds would be 800 requests while the device waits),
/// and <see cref="ProcessPendingAsync"/> fetches the queue in bounded batches in
/// the background so the device's next refresh picks the rates up.
///
/// Two things fill a missing date, and nothing else (never invent a rate):
/// a real feed document - even one dated earlier than the request, which is that
/// day's rate in force, RV.20 - is stored <c>published</c>; a date with no
/// document takes the most recent earlier published rate and is stored
/// <c>:carried-forward</c>, but only within <see cref="RateOptions.CarryBackWindowDays"/>
/// days. Further back than that the date is left honestly absent: a visible gap
/// beats a plausible wrong number in someone's cost history.
/// </summary>
public sealed class RateBackfillService
{
    private readonly RateRepository _repository;
    private readonly IReadOnlyList<IRateFeed> _feeds;
    private readonly RateOptions _options;
    private readonly ILogger<RateBackfillService> _logger;

    public RateBackfillService(
        RateRepository repository,
        IEnumerable<IRateFeed> feeds,
        IOptions<RateOptions> options,
        ILogger<RateBackfillService> logger)
    {
        _repository = repository;
        _feeds = feeds.ToArray();
        _options = options.Value;
        _logger = logger;
    }

    /// <summary>
    /// The trigger (called by GET /v1/rates/pack): queue every date in [from, to]
    /// that has no live row for at least one feed's publisher. Idempotent - a date
    /// already queued is left alone. Returns the number newly queued.
    /// </summary>
    public async Task<int> RecordRequestAsync(DateOnly from, DateOnly to, string baseCurrency, CancellationToken cancellationToken)
    {
        var sources = _feeds.Select(f => f.Source).ToHashSet(StringComparer.Ordinal);
        var live = await _repository.GetRangeAsync(from, to, baseCurrency, cancellationToken);

        var familiesByDate = live
            .GroupBy(r => r.Date)
            .ToDictionary(g => g.Key, g => g.Select(r => RateSources.Family(r.Source)).ToHashSet(StringComparer.Ordinal));

        var missing = new List<DateOnly>();
        for (var day = from; day <= to; day = day.AddDays(1))
        {
            if (!familiesByDate.TryGetValue(day, out var families) || !sources.IsSubsetOf(families))
            {
                missing.Add(day);
            }
        }

        return await _repository.RecordPendingAsync(missing, baseCurrency, cancellationToken);
    }

    /// <summary>
    /// One background pass: fetch the oldest <see cref="RateOptions.BackfillBatchSize"/>
    /// queued dates and carry back their gaps, then settle them. Runs oldest-first
    /// so a date always finds its earlier anchor already fetched. Returns counts
    /// for the pass; logs shape only.
    /// </summary>
    public async Task<RateBackfillResult> ProcessPendingAsync(CancellationToken cancellationToken)
    {
        var published = 0;
        var carried = 0;
        var sourcesFailed = 0;
        var processed = 0;

        foreach (var baseCurrency in _options.BaseCurrencies)
        {
            var dates = await _repository.GetPendingBatchAsync(baseCurrency, _options.BackfillBatchSize, cancellationToken);
            if (dates.Count == 0)
            {
                continue;
            }

            var result = await BackfillDatesAsync(dates, baseCurrency, cancellationToken);
            published += result.Published;
            carried += result.CarriedForward;
            sourcesFailed += result.SourcesFailed;
            processed += dates.Count;

            foreach (var date in dates)
            {
                await _repository.SettleAsync(date, baseCurrency, cancellationToken);
            }
        }

        if (processed > 0)
        {
            TankbookLog.RatesBackfill(_logger, processed, published, carried, sourcesFailed);
        }

        return new RateBackfillResult(processed, published, carried, sourcesFailed);
    }

    /// <summary>
    /// Backfill an explicit inclusive range, fetch + carry-back, in one pass. The
    /// L2 suite drives this directly against a recording feed; the hosted service
    /// drives <see cref="ProcessPendingAsync"/>, which calls the same core.
    /// </summary>
    public async Task<RateBackfillResult> BackfillRangeAsync(DateOnly from, DateOnly to, string baseCurrency, CancellationToken cancellationToken)
    {
        var dates = new List<DateOnly>();
        for (var day = from; day <= to; day = day.AddDays(1))
        {
            dates.Add(day);
        }

        return await BackfillDatesAsync(dates, baseCurrency, cancellationToken);
    }

    private async Task<RateBackfillResult> BackfillDatesAsync(IReadOnlyList<DateOnly> dates, string baseCurrency, CancellationToken cancellationToken)
    {
        if (dates.Count == 0)
        {
            return new RateBackfillResult(0, 0, 0, 0);
        }

        var live = (await _repository.GetAllForBaseAsync(baseCurrency, cancellationToken))
            .Where(r => !r.Deleted)
            .ToList();
        var familiesByDate = live
            .GroupBy(r => r.Date)
            .ToDictionary(g => g.Key, g => g.Select(r => RateSources.Family(r.Source)).ToHashSet(StringComparer.Ordinal));

        var published = 0;
        var sourcesFailed = 0;

        // Phase 1 - fetch. A date already carrying a publisher's row (published or
        // carried) is left alone: the append-only insert means a re-fetch is a no-op
        // anyway, and a carried row is a finished weekend, not work to redo.
        foreach (var date in dates)
        {
            familiesByDate.TryGetValue(date, out var families);
            foreach (var feed in _feeds)
            {
                if (families is not null && families.Contains(feed.Source))
                {
                    continue;
                }

                IReadOnlyList<RateQuote> quotes;
                try
                {
                    quotes = await feed.FetchAsync(date, baseCurrency, cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // A down feed must stay visible (RV.15 went unnoticed for weeks
                    // precisely because nothing downstream looked wrong): count the
                    // failure even while the carry-back below fills the gap.
                    sourcesFailed++;
                    _logger.LogWarning(ex, "Rate feed {Source} failed for {Date} / {Base}.", feed.Source, date, baseCurrency);
                    continue;
                }

                foreach (var quote in quotes)
                {
                    published += await _repository.UpsertAsync(
                        new RateInsert(date, baseCurrency, quote.Quote, quote.Rate, feed.Source),
                        cancellationToken);
                }
            }
        }

        // Phase 2 - carry BACK, bounded. Reload so the anchors include what phase 1
        // just fetched. For each quote with any live row, a date still missing it
        // takes the most recent earlier PUBLISHED rate, and only within the window -
        // a carried placeholder is never the anchor, so the 14 days is measured from
        // the genuine rate and a long outage resolves to absence, not a stale number.
        live = (await _repository.GetAllForBaseAsync(baseCurrency, cancellationToken))
            .Where(r => !r.Deleted)
            .ToList();

        var publishedByQuote = live
            .Where(r => !RateSources.IsCarried(r.Source))
            .GroupBy(r => r.Quote, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.OrderBy(r => r.Date).ToList(), StringComparer.Ordinal);
        var datesByQuote = live
            .GroupBy(r => r.Quote, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.Select(r => r.Date).ToHashSet(), StringComparer.Ordinal);

        var carried = 0;
        foreach (var date in dates)
        {
            foreach (var quote in datesByQuote.Keys)
            {
                if (datesByQuote[quote].Contains(date))
                {
                    continue;
                }

                if (!publishedByQuote.TryGetValue(quote, out var publishedRows))
                {
                    continue;
                }

                var earlier = publishedRows.LastOrDefault(r => r.Date < date);
                if (earlier is null || date.DayNumber - earlier.Date.DayNumber > _options.CarryBackWindowDays)
                {
                    // No earlier rate, or the nearest one is outside the window:
                    // leave the date absent rather than invent a rate.
                    continue;
                }

                carried += await _repository.UpsertAsync(
                    new RateInsert(date, baseCurrency, quote, earlier.Rate, RateSources.Carried(earlier.Source)),
                    cancellationToken);
            }
        }

        return new RateBackfillResult(dates.Count, published, carried, sourcesFailed);
    }
}
