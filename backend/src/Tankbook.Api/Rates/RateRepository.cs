using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Rates;

/// <summary>An exchange_rates row (migration 001 + 009). <c>Deleted</c> is true for a soft-deleted (corrected-away) row.</summary>
public sealed record ExchangeRateRow(DateOnly Date, string Base, string Quote, decimal Rate, string Source, bool Deleted);

/// <summary>A row the job wants to write. Upsert is append-only: it inserts only when no live row occupies the key.</summary>
public sealed record RateInsert(DateOnly Date, string Base, string Quote, decimal Rate, string Source);

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
