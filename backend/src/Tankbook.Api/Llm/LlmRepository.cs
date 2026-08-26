using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Llm;

/// <summary>The current period's metered usage for one account (migration 001's llm_usage ledger).</summary>
public sealed record LlmUsageRow(int Requests, long Tokens);

/// <summary>
/// Database access for the LLM gateway quota ledger (docs/API.md "LLM gateway
/// (Pro)", migration 001/010). Three queries: the account's tier (which decides
/// whether there is any allowance at all), the current period's usage (which
/// decides 429 vs proceed), and the atomic metering upsert. The upsert is a
/// single INSERT ... ON CONFLICT keyed by (account_id, period), so concurrent
/// requests cannot lose an increment; the row lock serializes them.
/// </summary>
public sealed class LlmRepository
{
    private readonly IDbConnection _db;

    public LlmRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>The account's tier (accounts.llm_tier, migration 010), or null when the account is gone.</summary>
    public async Task<string?> GetTierAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
                "SELECT llm_tier FROM accounts WHERE id = @AccountId",
                new { AccountId = accountId },
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

    /// <summary>The current period's usage, or null when the account has none this period.</summary>
    public async Task<LlmUsageRow?> GetUsageAsync(Guid accountId, DateOnly period, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<LlmUsageRow>(new CommandDefinition(
                "SELECT requests AS Requests, tokens AS Tokens FROM llm_usage WHERE account_id = @AccountId AND period = @Period",
                new { AccountId = accountId, Period = period },
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
    /// Atomically meters one successful extract: inserts the row or increments
    /// <c>requests</c> by one and <c>tokens</c> by the spent amount, returning the
    /// new totals. Called only after the provider answered, so a failed call never
    /// bills (docs/API.md: the client is only billed for a result it received).
    /// </summary>
    public async Task<LlmUsageRow> IncrementUsageAsync(
        Guid accountId,
        DateOnly period,
        long tokens,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleAsync<LlmUsageRow>(new CommandDefinition(
                """
                INSERT INTO llm_usage (account_id, period, requests, tokens)
                VALUES (@AccountId, @Period, 1, @Tokens)
                ON CONFLICT (account_id, period) DO UPDATE
                SET requests = llm_usage.requests + 1,
                    tokens   = llm_usage.tokens + EXCLUDED.tokens
                RETURNING requests AS Requests, tokens AS Tokens
                """,
                new { AccountId = accountId, Period = period, Tokens = tokens },
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
