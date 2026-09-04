using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Llm;

/// <summary>One retry pass's outcome (counts only - the give-up rows are logged individually).</summary>
public sealed record LlmLedgerRetryResult(int Attempted, int Landed, int Dropped);

/// <summary>
/// The ledger write queue's retry pass (migration 021, RV.53, docs/SECURITY.md
/// "The ledger write queue"). Runs over the llm_calls rows that could not be
/// inserted synchronously and retries them for a bounded time. The pass is a
/// scoped service so L2 tests drive it directly; the timer that runs it on a
/// schedule is <see cref="LlmLedgerRetryHostedService"/>, registered only
/// outside test hosts (the same pattern as the purge jobs).
///
/// Bounds, written here because they are commitments (docs/SECURITY.md):
/// a row is retried up to LlmCalls:MaxRetryAttempts with exponential backoff
/// from LlmCalls:RetryIntervalMinutes, and when it exhausts the bound it is
/// DROPPED - deleted from the queue with a shape-only Warning
/// (llm.call_retry_dropped) as the defined give-up outcome. An at-least-once
/// copy (INSERT ... ON CONFLICT DO NOTHING) means a crash between copy and
/// delete replays harmlessly.
/// </summary>
public sealed class LlmLedgerRetryService
{
    private readonly LlmLedgerPendingRepository _repository;
    private readonly LlmCallOptions _options;
    private readonly ILogger<LlmLedgerRetryService> _logger;
    private readonly TimeProvider _time;

    public LlmLedgerRetryService(
        LlmLedgerPendingRepository repository,
        IOptions<LlmCallOptions> options,
        ILogger<LlmLedgerRetryService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    /// <summary>One retry pass: copy every due row into llm_calls, dropping the ones that exhaust their bound.</summary>
    public async Task<LlmLedgerRetryResult> RetryDueAsync(CancellationToken cancellationToken)
    {
        var now = _time.GetUtcNow();
        var due = await _repository.ListDueAsync(now, cancellationToken);
        var landed = 0;
        var dropped = 0;

        foreach (var row in due)
        {
            try
            {
                await _repository.CopyToCallsAsync(row.Id, cancellationToken);
                await _repository.DeleteAsync(row.Id, cancellationToken);
                landed++;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception)
            {
                // The row still cannot land. Give up when the retry bound is
                // exhausted - a defined outcome, not an infinite retry: the row
                // is deleted and the Warning names which account and outcome it
                // was (shape only, hard rule 12).
                var attempts = row.Attempts + 1;
                if (attempts >= _options.MaxRetryAttempts)
                {
                    await _repository.DeleteAsync(row.Id, cancellationToken);
                    dropped++;
                    TankbookLog.LlmCallRetryDropped(_logger, row.AccountId, row.Outcome, attempts);
                }
                else
                {
                    await _repository.ScheduleRetryAsync(
                        row.Id, attempts, now + BackoffDelay(attempts), cancellationToken);
                }
            }
        }

        if (landed > 0)
        {
            TankbookLog.LlmCallRetryLanded(_logger, landed);
        }

        return new LlmLedgerRetryResult(due.Count, landed, dropped);
    }

    /// <summary>Exponential backoff from the configured interval, doubling per attempt, capped at a 32x step.</summary>
    private TimeSpan BackoffDelay(int attempts)
    {
        var shift = Math.Min(attempts - 1, 5);
        return _options.RetryInterval * (1 << shift);
    }
}
