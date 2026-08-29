namespace Tankbook.Api.Blobs;

/// <summary>
/// The cross-account orphan sweep (docs/API.md "Attachments", docs/PRACTICES.md
/// S11, PR.18). It enumerates the accounts that hold blob state and runs the
/// per-account <see cref="BlobService.SweepOrphansAsync"/> over each - which
/// removes unreferenced blobs past the grace period and clears stale pending
/// rows. The hosted timer that calls it on a schedule lives in
/// <see cref="BlobSweepHostedService"/>, which is not registered in test hosts;
/// L2 tests drive <see cref="SweepAllAsync"/> directly.
/// </summary>
public sealed class BlobSweepService
{
    private readonly BlobRepository _repository;
    private readonly BlobService _blobs;

    public BlobSweepService(BlobRepository repository, BlobService blobs)
    {
        _repository = repository;
        _blobs = blobs;
    }

    /// <summary>One sweep pass across every account that has blob state. Returns the number of orphaned blobs removed.</summary>
    public async Task<int> SweepAllAsync(CancellationToken cancellationToken)
    {
        var accounts = await _repository.ListAccountsWithBlobsAsync(cancellationToken);

        var total = 0;
        foreach (var accountId in accounts)
        {
            total += await _blobs.SweepOrphansAsync(accountId, cancellationToken);
        }

        return total;
    }
}
