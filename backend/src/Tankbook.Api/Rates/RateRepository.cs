using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Rates;

/// <summary>An exchange_rates row (migration 001 + 009). <c>Deleted</c> is true for a soft-deleted (corrected-away) row.</summary>
public sealed record ExchangeRateRow(DateOnly Date, string Base, string Quote, decimal Rate, string Source, bool Deleted);

/// <summary>A row the job wants to write. Upsert is append-only: it inserts only when no live row occupies the key.</summary>
public sealed record RateInsert(DateOnly Date, string Base, string Quote, decimal Rate, string Source);

/// <summary>One answered-empty record: this feed was asked for this (date, base) and returned no document.</summary>
public sealed record AnsweredRateRow(DateOnly Date, string Base, string Source);

/// <summary>
/// Database access for <c>exchange_rates</c> (docs/SCHEMA.md "Reference data ->
/// Exchange rates"). Published rows are append-only: <see cref="UpsertAsync"/>
/// never rewrites one published row with another, so a re-fetch with a different
/// value leaves the published value intact. The one exception is a
/// <c>:carried-forward</c> placeholder: a published row may supersede it for the
/// same (date, base, quote), because the placeholder held a previous day's value
/// and must not permanently displace the genuine rate published later that day
/// (RV.36). The manual correction path is <see cref="SoftDeleteAsync"/> (mark a
/// bad day's rows deleted) followed by a re-fetch, which inserts a fresh live
/// row beside the soft-deleted one (migration 009's partial unique index frees
/// the slot).
/// </summary>
public sealed class RateRepository
{
    private readonly IDbConnection _db;

    public RateRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>
    /// Inserts a published or carried-forward row. A published row may supersede
    /// a <c>:carried-forward</c> placeholder for the same (date, base, quote),
    /// because the placeholder is not real data; a published row never overwrites
    /// another published row, and a carried row never overwrites another carried
    /// row. Returns 1 when a row was inserted or superseded, 0 when the slot
    /// already held a row that wins.
    /// </summary>
    public async Task<int> UpsertAsync(RateInsert row, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var isCarried = RateSources.IsCarried(row.Source);
            return await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO exchange_rates (date, base, quote, rate, source)
                VALUES (@Date, @Base, @Quote, @Rate, @Source)
                ON CONFLICT (date, base, quote) WHERE deleted_at IS NULL
                DO UPDATE SET rate = EXCLUDED.rate, source = EXCLUDED.source
                WHERE exchange_rates.source LIKE @CarriedLike AND NOT @IsCarried
                """,
                new
                {
                    row.Date,
                    Base = row.Base,
                    Quote = row.Quote,
                    row.Rate,
                    row.Source,
                    IsCarried = isCarried,
                    CarriedLike = "%" + RateSources.CarriedSuffix,
                },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>The live quotes for one date and base, ordered by quote. Empty when the date has no data.</summary>
    public async Task<IReadOnlyList<ExchangeRateRow>> GetForDateAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<ExchangeRateRow>(new CommandDefinition(
                """
                SELECT date AS Date, base AS Base, quote AS Quote, rate AS Rate, source AS Source,
                       deleted_at IS NOT NULL AS Deleted
                FROM exchange_rates
                WHERE date = @Date AND base = @Base AND deleted_at IS NULL
                ORDER BY quote
                """,
                new { Date = date, Base = baseCurrency },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>The live quotes for an inclusive date range and base, ordered by date then quote.</summary>
    public async Task<IReadOnlyList<ExchangeRateRow>> GetRangeAsync(DateOnly from, DateOnly to, string baseCurrency, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<ExchangeRateRow>(new CommandDefinition(
                """
                SELECT date AS Date, base AS Base, quote AS Quote, rate AS Rate, source AS Source,
                       deleted_at IS NOT NULL AS Deleted
                FROM exchange_rates
                WHERE date BETWEEN @From AND @To AND base = @Base AND deleted_at IS NULL
                ORDER BY date, quote
                """,
                new { From = from, To = to, Base = baseCurrency },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// Every row (live and soft-deleted) for one base, ordered by date - the
    /// working set the carry-forward pass uses to find gaps and last-published
    /// values. The daily job reads the whole base because the table is small and
    /// the pass must stay idempotent.
    /// </summary>
    public async Task<IReadOnlyList<ExchangeRateRow>> GetAllForBaseAsync(string baseCurrency, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<ExchangeRateRow>(new CommandDefinition(
                """
                SELECT date AS Date, base AS Base, quote AS Quote, rate AS Rate, source AS Source,
                       deleted_at IS NOT NULL AS Deleted
                FROM exchange_rates
                WHERE base = @Base
                ORDER BY date, quote
                """,
                new { Base = baseCurrency },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// The manual correction step (docs/SCHEMA.md): soft-deletes live rows for a
    /// date and base, optionally restricted to one quote. Returns the number of
    /// rows marked. Soft-deleted rows stop being served but remain physically, so
    /// a re-fetch can insert a corrected row without rewriting history.
    /// </summary>
    public async Task<int> SoftDeleteAsync(DateOnly date, string baseCurrency, string? quote, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                """
                UPDATE exchange_rates SET deleted_at = now()
                WHERE date = @Date AND base = @Base
                  AND (@Quote IS NULL OR quote = @Quote)
                  AND deleted_at IS NULL
                """,
                new { Date = date, Base = baseCurrency, Quote = quote },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// Records the backfill demand (docs/SCHEMA.md "Exchange rates"): every date a
    /// device asked for but that has no rate yet, keyed (base, date). Idempotent -
    /// a date already queued is left alone, so a re-request adds nothing.
    /// </summary>
    public async Task<int> RecordPendingAsync(IReadOnlyList<DateOnly> dates, string baseCurrency, CancellationToken cancellationToken)
    {
        if (dates.Count == 0)
        {
            return 0;
        }

        var opened = await OpenIfNeededAsync();
        try
        {
            // Npgsql maps DateTime[] to a timestamp array; the cast folds it to
            // the table's date column. One round trip for the whole gap, not one
            // per date.
            var stamps = dates.Select(d => d.ToDateTime(TimeOnly.MinValue)).ToArray();
            return await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO rate_backfill (date, base)
                SELECT d, @Base FROM unnest(@Dates::date[]) AS d
                ON CONFLICT DO NOTHING
                """,
                new { Dates = stamps, Base = baseCurrency },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>The oldest pending (date, base) rows for a base, up to <paramref name="batchSize"/> - the bounded burst one pass fetches.</summary>
    public async Task<IReadOnlyList<DateOnly>> GetPendingBatchAsync(string baseCurrency, int batchSize, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<DateOnly>(new CommandDefinition(
                """
                SELECT date FROM rate_backfill
                WHERE base = @Base
                ORDER BY date
                LIMIT @BatchSize
                """,
                new { Base = baseCurrency, BatchSize = batchSize },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// Records that a feed was asked for a (date, base) and answered empty - no
    /// document, and no earlier published rate within the carry-back window. The
    /// record is what lets <c>RecordRequestAsync</c> stop re-enqueueing a date
    /// that is genuinely unfillable (RV.50). Idempotent - re-answering is a no-op.
    /// </summary>
    public async Task<int> MarkAnsweredAsync(DateOnly date, string baseCurrency, string source, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO rate_backfill_answered (date, base, source)
                VALUES (@Date, @Base, @Source)
                ON CONFLICT DO NOTHING
                """,
                new { Date = date, Base = baseCurrency, Source = source },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>The answered-empty records for an inclusive date range and base, ordered by date then source - the set <c>RecordRequestAsync</c> consults before enqueueing.</summary>
    public async Task<IReadOnlyList<AnsweredRateRow>> GetAnsweredAsync(DateOnly from, DateOnly to, string baseCurrency, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<AnsweredRateRow>(new CommandDefinition(
                """
                SELECT date AS Date, base AS Base, source AS Source
                FROM rate_backfill_answered
                WHERE date BETWEEN @From AND @To AND base = @Base
                ORDER BY date, source
                """,
                new { From = from, To = to, Base = baseCurrency },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>
    /// Reopens answered dates inside an inclusive window for one feed: a fresh
    /// published rate is a new carry-back anchor, so dates answered "nothing
    /// published" that now sit within the window of it must be tried again. The
    /// answered markers are cleared and the dates re-enqueued in one step; a date
    /// already in the queue is left alone (<c>ON CONFLICT DO NOTHING</c>). Returns
    /// the number of dates re-enqueued.
    /// </summary>
    public async Task<int> ReopenAnsweredAsync(DateOnly from, DateOnly to, string baseCurrency, string source, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var requeued = await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO rate_backfill (date, base)
                SELECT date, base FROM rate_backfill_answered
                WHERE base = @Base AND source = @Source AND date BETWEEN @From AND @To
                ON CONFLICT DO NOTHING
                """,
                new { From = from, To = to, Base = baseCurrency, Source = source },
                cancellationToken: cancellationToken));

            await _db.ExecuteAsync(new CommandDefinition(
                """
                DELETE FROM rate_backfill_answered
                WHERE base = @Base AND source = @Source AND date BETWEEN @From AND @To
                """,
                new { From = from, To = to, Base = baseCurrency, Source = source },
                cancellationToken: cancellationToken));

            return requeued;
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Removes a (date, base) from the queue once the backfill has attempted it - filled or honestly absent, it is no longer pending.</summary>
    public async Task<int> SettleAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                """
                DELETE FROM rate_backfill WHERE base = @Base AND date = @Date
                """,
                new { Base = baseCurrency, Date = date },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    private async Task<bool> OpenIfNeededAsync()
    {
        if (_db.State == ConnectionState.Open)
        {
            return false;
        }

        await ((DbConnection)_db).OpenAsync();
        return true;
    }
}
