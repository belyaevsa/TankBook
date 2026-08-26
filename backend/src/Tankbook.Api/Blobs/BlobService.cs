using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Blobs;

/// <summary>POST /blobs/begin outcome.</summary>
public enum BeginStatus
{
    Exists,
    Upload,
    TooLarge,
    QuotaExceeded,
    DeviceRevoked,
}

/// <summary>POST /blobs/begin outcome with the upload payload when the blob is new.</summary>
public sealed record BeginOutcome(BeginStatus Status, BlobBeginResponse? Response);

/// <summary>POST /blobs/commit outcome.</summary>
public enum CommitStatus
{
    Committed,
    NotBegun,
    NotUploaded,
    SizeMismatch,
    DeviceRevoked,
}

/// <summary>POST /blobs/commit outcome.</summary>
public sealed record CommitOutcome(CommitStatus Status);

/// <summary>GET /blobs/{sha256} outcome.</summary>
public enum GetStatus
{
    Redirect,
    NotFound,
    DeviceRevoked,
}

/// <summary>GET /blobs/{sha256} outcome with the presigned URL when the blob is owned.</summary>
public sealed record GetOutcome(GetStatus Status, string? Url);

/// <summary>
/// Orchestrates the blob pipeline (docs/API.md "Attachments", docs/SYNC.md
/// "Attachments: the blob pipeline"). It logs blob.begin / blob.commit / blob.get
/// with the sha256, size, content type, dedupe outcome and quota percentage -
/// never the presigned URL (hard rule 12: a presigned URL is a bearer credential
/// in a query string).
/// </summary>
public sealed class BlobService
{
    private readonly BlobRepository _repository;
    private readonly IBlobStorage _storage;
    private readonly BlobOptions _options;
    private readonly ILogger<BlobService> _logger;
    private readonly TimeProvider _time;

    public BlobService(
        BlobRepository repository,
        IBlobStorage storage,
        IOptions<BlobOptions> options,
        ILogger<BlobService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _storage = storage;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    public async Task<BeginOutcome> BeginAsync(
        Guid accountId,
        Guid deviceId,
        string sha256,
        long size,
        BlobKind kind,
        string contentType,
        CancellationToken cancellationToken)
    {
        if (!await _repository.IsDeviceActiveAsync(accountId, deviceId, cancellationToken))
        {
            return new BeginOutcome(BeginStatus.DeviceRevoked, null);
        }

        // Dedupe first: a blob that already exists consumes no quota.
        if (await _repository.GetBlobAsync(accountId, sha256, cancellationToken) is not null)
        {
            TankbookLog.BlobBegin(_logger, sha256, size, contentType, "hit", null);
            return new BeginOutcome(BeginStatus.Exists, BlobBeginResponse.Exists);
        }

        var cap = BlobContentTypes.SizeCap(_options, kind);
        if (size > cap)
        {
            return new BeginOutcome(BeginStatus.TooLarge, null);
        }

        var used = await _repository.GetUsedBytesAsync(accountId, cancellationToken);
        if (used + size > _options.QuotaBytes)
        {
            TankbookLog.BlobBegin(_logger, sha256, size, contentType, "miss", QuotaPercent(used));
            return new BeginOutcome(BeginStatus.QuotaExceeded, null);
        }

        var key = BlobKeys.Key(accountId, sha256);
        await _repository.UpsertPendingAsync(accountId, sha256, size, contentType, cancellationToken);

        var presigned = _storage.CreateUploadUrl(key, _options.UploadPresignLifetime);
        TankbookLog.BlobBegin(_logger, sha256, size, contentType, "miss", QuotaPercent(used));

        return new BeginOutcome(
            BeginStatus.Upload,
            BlobBeginResponse.Upload(presigned.Url, presigned.ExpiresAt));
    }

    public async Task<CommitOutcome> CommitAsync(
        Guid accountId,
        Guid deviceId,
        string sha256,
        CancellationToken cancellationToken)
    {
        if (!await _repository.IsDeviceActiveAsync(accountId, deviceId, cancellationToken))
        {
            return new CommitOutcome(CommitStatus.DeviceRevoked);
        }

        if (await _repository.GetBlobAsync(accountId, sha256, cancellationToken) is not null)
        {
            // Already committed (idempotent replay of the commit).
            return new CommitOutcome(CommitStatus.Committed);
        }

        var pending = await _repository.GetPendingAsync(accountId, sha256, cancellationToken);
        if (pending is null)
        {
            return new CommitOutcome(CommitStatus.NotBegun);
        }

        var key = BlobKeys.Key(accountId, sha256);
        var storedSize = await _storage.GetObjectSizeAsync(key, cancellationToken);
        if (storedSize is null)
        {
            return new CommitOutcome(CommitStatus.NotUploaded);
        }

        if (storedSize.Value != pending.SizeBytes)
        {
            return new CommitOutcome(CommitStatus.SizeMismatch);
        }

        await _repository.CommitAsync(accountId, sha256, pending.SizeBytes, key, cancellationToken);

        var used = await _repository.GetUsedBytesAsync(accountId, cancellationToken);
        TankbookLog.BlobCommit(_logger, sha256, pending.SizeBytes, pending.ContentType, QuotaPercent(used));

        return new CommitOutcome(CommitStatus.Committed);
    }

    public async Task<GetOutcome> GetAsync(
        Guid accountId,
        Guid deviceId,
        string sha256,
        CancellationToken cancellationToken)
    {
        if (!await _repository.IsDeviceActiveAsync(accountId, deviceId, cancellationToken))
        {
            return new GetOutcome(GetStatus.DeviceRevoked, null);
        }

        var blob = await _repository.GetBlobAsync(accountId, sha256, cancellationToken);
        if (blob is null)
        {
            return new GetOutcome(GetStatus.NotFound, null);
        }

        // Only mint the presigned URL after the blob is known to be owned - a
        // 404 for another account's sha256 must never have produced a URL.
        var key = BlobKeys.Key(accountId, sha256);
        var presigned = _storage.CreateDownloadUrl(key, _options.DownloadPresignLifetime);
        TankbookLog.BlobGet(_logger, sha256, _options.DownloadPresignMinutes * 60);

        return new GetOutcome(GetStatus.Redirect, presigned.Url);
    }

    /// <summary>
    /// Deletes the account's orphaned blobs from both storage and the index, and
    /// clears stale pending rows. Returns the number of blobs removed.
    /// </summary>
    public async Task<int> SweepOrphansAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var cutoff = _time.GetUtcNow() - _options.OrphanGracePeriod;
        var orphans = await _repository.FindOrphanSha256sAsync(accountId, cutoff, cancellationToken);

        if (orphans.Count > 0)
        {
            var keys = orphans.Select(sha256 => BlobKeys.Key(accountId, sha256)).ToList();
            await _storage.DeleteManyAsync(keys, cancellationToken);
            await _repository.DeleteBlobsAsync(accountId, orphans, cancellationToken);
        }

        await _repository.DeleteStalePendingAsync(accountId, cutoff, cancellationToken);

        if (orphans.Count > 0)
        {
            TankbookLog.BlobSweep(_logger, accountId, orphans.Count);
        }

        return orphans.Count;
    }

    /// <summary>
    /// Purges the account's whole blob prefix (docs/SYNC.md: account deletion
    /// purges the whole prefix). Deletes the index rows and every storage object
    /// under {account_id}/. Returns the number of blobs removed.
    /// </summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var keys = await _repository.DeleteAccountBlobsAsync(accountId, cancellationToken);

        if (keys.Count > 0)
        {
            await _storage.DeleteManyAsync(keys, cancellationToken);
        }

        // Storage may hold objects the index lost track of; clear the prefix
        // wholesale so account deletion truly deletes everything.
        var remaining = await _storage.ListKeysAsync(BlobKeys.Prefix(accountId), cancellationToken);
        if (remaining.Count > 0)
        {
            await _storage.DeleteManyAsync(remaining, cancellationToken);
        }

        if (keys.Count > 0 || remaining.Count > 0)
        {
            TankbookLog.BlobPurge(_logger, accountId, keys.Count + remaining.Count);
        }

        return keys.Count + remaining.Count;
    }

    private int QuotaPercent(long usedBytes) =>
        _options.QuotaBytes <= 0
            ? 0
            : (int)Math.Min(100, usedBytes * 100 / _options.QuotaBytes);
}
