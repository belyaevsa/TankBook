using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Llm;

/// <summary>One queued ledger row due for a retry attempt (id + the Safe context its give-up log needs).</summary>
public sealed record LlmLedgerPendingRow(Guid Id, Guid AccountId, string Outcome, int Attempts);

/// <summary>
/// Database access for the ledger write queue (migration 021, RV.53,
/// docs/SECURITY.md "The ledger write queue"): llm_calls rows that could not be
/// inserted synchronously, waiting for a bounded retry. The queue holds ROWS,
/// never image bytes - the rendition is content-addressed in blob storage and
/// only its sha256 rides on the row (docs/SECURITY.md: the server retains no
/// image bytes, so a rendition that could not be written is dropped, not queued).
///
/// The drain copy is idempotent (INSERT ... ON CONFLICT (id) DO NOTHING), so a
/// worker that dies between the copy and the delete replays the row and the
/// conflict resolves it - at-least-once, the same ack discipline the delivery
/// outbox uses.
/// </summary>
public sealed class LlmLedgerPendingRepository
{
    private readonly IDbConnection _db;

    public LlmLedgerPendingRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>Queues one ledger row for a bounded retry. First attempt is due immediately.</summary>
    public async Task EnqueueAsync(LlmCallInsert call, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO llm_ledger_pending
                    (id, account_id, device_id, kind, model_id, vendor, outcome, category,
                     prompt_tokens, completion_tokens, thinking_enabled,
                     input_price_per_token, output_price_per_token, cost, currency,
                     prompt_sha256, prompt_body, response_body, thinking_body, duration_ms)
                VALUES
                    (@Id, @AccountId, @DeviceId, @Kind, @ModelId, @Vendor, @Outcome, @Category,
                     @PromptTokens, @CompletionTokens, @ThinkingEnabled,
                     @InputPricePerToken, @OutputPricePerToken, @Cost, @Currency,
                     @PromptSha256, @PromptBody, @ResponseBody, @ThinkingBody, @DurationMs)
                """,
                call,
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

    /// <summary>The rows whose next attempt is due, oldest first, with the Safe context the give-up decision needs.</summary>
    public async Task<IReadOnlyList<LlmLedgerPendingRow>> ListDueAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<LlmLedgerPendingRow>(new CommandDefinition(
                """
                SELECT id AS Id, account_id AS AccountId, outcome AS Outcome, attempts AS Attempts
                FROM llm_ledger_pending
                WHERE next_attempt_at <= @Now
                ORDER BY next_attempt_at, id
                """,
                new { Now = now },
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
    /// Copies one pending row into llm_calls. Idempotent: when the row is
    /// already there (a worker died between the copy and the delete and is
    /// replaying), the conflict resolves to 0 rows affected and the pending row
    /// is still safe to delete - the audit record exists.
    /// </summary>
    public async Task CopyToCallsAsync(Guid id, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO llm_calls
                    (id, account_id, device_id, kind, model_id, vendor, outcome, category,
                     prompt_tokens, completion_tokens, thinking_enabled,
                     input_price_per_token, output_price_per_token, cost, currency,
                     prompt_sha256, prompt_body, response_body, thinking_body, duration_ms)
                SELECT
                    id, account_id, device_id, kind, model_id, vendor, outcome, category,
                    prompt_tokens, completion_tokens, thinking_enabled,
                    input_price_per_token, output_price_per_token, cost, currency,
                    prompt_sha256, prompt_body, response_body, thinking_body, duration_ms
                FROM llm_ledger_pending
                WHERE id = @Id
                ON CONFLICT (id) DO NOTHING
                """,
                new { Id = id },
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

    /// <summary>Deletes one pending row (landed, dropped after give-up, or drained).</summary>
    public async Task DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM llm_ledger_pending WHERE id = @Id",
                new { Id = id },
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

    /// <summary>Records a failed attempt and schedules the next one (exponential backoff).</summary>
    public async Task ScheduleRetryAsync(Guid id, int attempts, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                UPDATE llm_ledger_pending
                SET attempts = @Attempts, next_attempt_at = @NextAttemptAt
                WHERE id = @Id
                """,
                new { Id = id, Attempts = attempts, NextAttemptAt = nextAttemptAt },
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

    /// <summary>Deletes the rows past the retention cutoff that never landed, and returns how many (the retention purge's job).</summary>
    public async Task<int> PurgeStaleAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM llm_ledger_pending WHERE created_at <= @Cutoff",
                new { Cutoff = cutoff },
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

    /// <summary>Deletes every pending row an account owns (account-deletion purge; also covered by the cascade FK).</summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM llm_ledger_pending WHERE account_id = @AccountId",
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
