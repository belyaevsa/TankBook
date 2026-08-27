using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Import;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Account;

/// <summary>One purge pass's outcome (counts only - never values).</summary>
public sealed record AccountPurgeResult(int AccountsPurged, long RecordsPurged, long BlobsPurged);

/// <summary>
/// The account-lifecycle job (docs/SYNC.md "Offline & failure behavior"): after
/// the grace period it purges tombstoned accounts' records and calls
/// <see cref="BlobService.PurgeAccountAsync"/>, and it makes the per-account
/// orphan sweep reachable from the same service. The purge runs only when
/// invoked directly (L2 tests drive the method, never the clock); the timer that
/// calls it on a schedule lives in <see cref="AccountPurgeHostedService"/>,
/// which is not registered in test hosts.
/// </summary>
public sealed class AccountPurgeService
{
    private readonly AccountRepository _repository;
    private readonly BlobService _blobs;
    private readonly ImportService _imports;
    private readonly AccountOptions _options;
    private readonly LoggingOptions _loggingOptions;
    private readonly ILogger<AccountPurgeService> _logger;
    private readonly TimeProvider _time;

    public AccountPurgeService(
        AccountRepository repository,
        BlobService blobs,
        ImportService imports,
        IOptions<AccountOptions> options,
        LoggingOptions loggingOptions,
        ILogger<AccountPurgeService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _blobs = blobs;
        _imports = imports;
        _options = options.Value;
        _loggingOptions = loggingOptions;
        _logger = logger;
        _time = time;
    }

    /// <summary>
    /// One purge pass: deletes records and blob storage for every account
    /// tombstoned longer ago than the grace period, and nothing else. An account
    /// tombstoned within the window is untouched - records and blobs both stay.
    /// Stored import files count as the account's data, so they are purged too
    /// (docs/SECURITY.md: deleting the account deletes these).
    /// </summary>
    public async Task<AccountPurgeResult> PurgeDueAccountsAsync(CancellationToken cancellationToken)
    {
        var cutoff = _time.GetUtcNow() - _options.DeletionGracePeriod;
        var due = await _repository.ListDueAccountsAsync(cutoff, cancellationToken);

        long recordsPurged = 0;
        long blobsPurged = 0;

        foreach (var account in due)
        {
            var records = await _repository.CountRecordsAsync(account.Id, cancellationToken);
            var blobs = await _blobs.PurgeAccountAsync(account.Id, cancellationToken);
            await _imports.PurgeAccountAsync(account.Id, cancellationToken);
            await _repository.DeleteAccountAsync(account.Id, cancellationToken);

            var accountHash = AccountHash.Compute(account.Email, _loggingOptions.HashSalt);
            var graceEndsAt = new DateTimeOffset(DateTime.SpecifyKind(account.DeletedAt, DateTimeKind.Utc)) + _options.DeletionGracePeriod;
            TankbookLog.AccountDelete(_logger, accountHash, records, blobs, graceEndsAt);

            recordsPurged += records;
            blobsPurged += blobs;
        }

        return new AccountPurgeResult(due.Count, recordsPurged, blobsPurged);
    }

    /// <summary>The per-account orphan sweep (docs/SYNC.md hygiene), reachable from the same job.</summary>
    public Task<int> SweepOrphansAsync(Guid accountId, CancellationToken cancellationToken)
        => _blobs.SweepOrphansAsync(accountId, cancellationToken);
}
