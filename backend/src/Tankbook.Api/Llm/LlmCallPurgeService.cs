using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Llm;

/// <summary>
/// The 30-day retention purge for the call ledger's content, and the account
/// deletion purge (docs/SECURITY.md "LLM call ledger": "Purge is a job, not a
/// hope"). It deletes the prompt/response/thinking bodies and the prompt
/// rendition blob, and leaves the row itself - the spend ledger - intact,
/// including account_id and the sha256 reference (product owner, 2026-09-03:
/// per-account cost history survives deletion; sha256 is content-addressed, so
/// an identical image re-uploaded later dedupes to the same hash - a weak
/// re-identification path, accepted rather than redesigned around).
/// </summary>
public sealed class LlmCallPurgeService
{
    private readonly LlmCallRepository _repository;
    private readonly LlmLedgerPendingRepository _ledgerPending;
    private readonly IBlobStorage _storage;
    private readonly LlmCallOptions _options;
    private readonly ILogger<LlmCallPurgeService> _logger;
    private readonly TimeProvider _time;

    public LlmCallPurgeService(
        LlmCallRepository repository,
        LlmLedgerPendingRepository ledgerPending,
        IBlobStorage storage,
        IOptions<LlmCallOptions> options,
        ILogger<LlmCallPurgeService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _ledgerPending = ledgerPending;
        _storage = storage;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    /// <summary>
    /// One retention pass: for every call past the cutoff that still carries
    /// content, delete its rendition blob and null its bodies. The row and its
    /// ledger fields (model, vendor, tokens, cost, outcome, sha256) survive.
    /// The same pass also drops ledger-write-queue rows still pending past the
    /// cutoff (RV.53) - the 30-day number governs that queue's staging too, so
    /// a row a wedged retry worker never resolved cannot sit there forever.
    /// </summary>
    public async Task<int> PurgeDueAsync(CancellationToken cancellationToken)
    {
        var cutoff = _time.GetUtcNow() - _options.RetentionPeriod;
        var due = await _repository.ListDueAsync(cutoff, cancellationToken);

        if (due.Count > 0)
        {
            // Delete the renditions of the due rows, but keep any sha still
            // referenced by a call inside the window: content-addressing dedupes
            // two identical images to one hash, so the shared blob must survive
            // until the last reference expires.
            var liveShas = (await _repository.ListLiveSha256sAsync(cutoff, cancellationToken))
                .ToHashSet(StringComparer.Ordinal);

            var renditions = due
                .Where(row => row.PromptSha256 is not null && !liveShas.Contains(row.PromptSha256))
                .Select(row => (AccountId: row.AccountId, Sha256: row.PromptSha256!))
                .Distinct()
                .ToList();

            if (renditions.Count > 0)
            {
                await _storage.DeleteManyAsync(
                    renditions.Select(r => LlmCallKeys.PromptKey(r.AccountId, r.Sha256)).ToList(),
                    cancellationToken);
            }

            await _repository.PurgeContentAsync(due.Select(r => r.Id).ToList(), cancellationToken);

            TankbookLog.LlmCallPurge(_logger, due.Count);
        }

        // The pending queue shares the same 30-day ceiling. This part runs even
        // when nothing was due in llm_calls: it is the one guarantee a wedged
        // retry worker cannot give (its own rows would otherwise sit forever).
        var stalePending = await _ledgerPending.PurgeStaleAsync(cutoff, cancellationToken);
        if (stalePending > 0)
        {
            TankbookLog.LlmPendingPurge(_logger, stalePending);
        }

        return due.Count;
    }

    /// <summary>
    /// Account-deletion purge: delete the account's prompt renditions, null the
    /// bodies on every row the account owns, and drop any ledger-write-queue
    /// rows still pending for it (RV.53 - a queued row belongs to the account
    /// that is being deleted; the cascade FK is the backstop, this is the
    /// explicit purge). Called from the account purge after the blob prefix
    /// purge, so the rendition deletion is idempotent with it - the prefix
    /// purge already removed the objects, and this nulls what no prefix purge
    /// can (the columns). The rows survive.
    /// </summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var sha256s = await _repository.ListAccountSha256sAsync(accountId, cancellationToken);
        if (sha256s.Count > 0)
        {
            var keys = sha256s.Select(sha256 => LlmCallKeys.PromptKey(accountId, sha256)).ToList();
            await _storage.DeleteManyAsync(keys, cancellationToken);
        }

        await _repository.PurgeAccountContentAsync(accountId, cancellationToken);

        var pendingPurged = await _ledgerPending.PurgeAccountAsync(accountId, cancellationToken);
        if (pendingPurged > 0)
        {
            TankbookLog.LlmPendingPurge(_logger, pendingPurged);
        }

        if (sha256s.Count > 0)
        {
            TankbookLog.LlmCallPurge(_logger, sha256s.Count);
        }

        return sha256s.Count;
    }
}
