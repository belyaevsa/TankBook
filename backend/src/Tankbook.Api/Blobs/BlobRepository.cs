using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Blobs;

/// <summary>A committed blobs row (migration 001).</summary>
public sealed record BlobRow(long SizeBytes, string StorageRef, DateTime CreatedAt);

/// <summary>A pending-upload row (migration 006): a begin whose commit has not landed yet.</summary>
public sealed record PendingBlobRow(long SizeBytes, string ContentType, DateTime CreatedAt);

/// <summary>
/// Database access for the blob pipeline (docs/API.md "Attachments"). A blobs
/// row exists only for a committed, size-verified object; blob_pending holds the
/// declared size/content-type between begin and commit. Quota is derived from
/// the index (SUM of size_bytes), never stored - the index is the source of
/// truth, so it cannot drift (the same principle as hard rule 2's
/// derive-never-store).
/// </summary>
public sealed class BlobRepository
{
    private readonly IDbConnection _db;

    public BlobRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>True when the account is live and the device is registered and not revoked (mirrors sync's 410 check).</summary>
    public async Task<bool> IsDeviceActiveAsync(Guid accountId, Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleAsync<bool>(new CommandDefinition(
                """
                SELECT EXISTS (
                    SELECT 1 FROM accounts a
                    JOIN devices d ON d.account_id = a.id AND d.id = @DeviceId
                    WHERE a.id = @AccountId AND a.deleted_at IS NULL AND d.revoked_at IS NULL
                )
                """,
                new { AccountId = accountId, DeviceId = deviceId },
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

    public async Task<BlobRow?> GetBlobAsync(Guid accountId, string sha256, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<BlobRow>(new CommandDefinition(
                "SELECT size_bytes AS SizeBytes, storage_ref AS StorageRef, created_at AS CreatedAt FROM blobs WHERE account_id = @AccountId AND sha256 = @Sha256",
                new { AccountId = accountId, Sha256 = sha256 },
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

    public async Task<PendingBlobRow?> GetPendingAsync(Guid accountId, string sha256, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<PendingBlobRow>(new CommandDefinition(
                "SELECT size_bytes AS SizeBytes, content_type AS ContentType, created_at AS CreatedAt FROM blob_pending WHERE account_id = @AccountId AND sha256 = @Sha256",
                new { AccountId = accountId, Sha256 = sha256 },
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

    /// <summary>Remembers a begin's declared size and content type (idempotent re-begin).</summary>
    public async Task UpsertPendingAsync(
        Guid accountId,
        string sha256,
        long sizeBytes,
        string contentType,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO blob_pending (account_id, sha256, size_bytes, content_type)
                VALUES (@AccountId, @Sha256, @SizeBytes, @ContentType)
                ON CONFLICT (account_id, sha256)
                DO UPDATE SET size_bytes = EXCLUDED.size_bytes, content_type = EXCLUDED.content_type, created_at = now()
                """,
                new { AccountId = accountId, Sha256 = sha256, SizeBytes = sizeBytes, ContentType = contentType },
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
    /// Consumes the pending row and inserts the blobs row in one transaction.
    /// Idempotent: when the blobs row already exists (a replayed commit) the
    /// insert does nothing and the pending row is still cleared.
    /// </summary>
    public async Task CommitAsync(
        Guid accountId,
        string sha256,
        long sizeBytes,
        string storageRef,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var connection = (DbConnection)_db;
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                await _db.ExecuteAsync(new CommandDefinition(
                    "DELETE FROM blob_pending WHERE account_id = @AccountId AND sha256 = @Sha256",
                    new { AccountId = accountId, Sha256 = sha256 },
                    transaction: transaction,
                    cancellationToken: cancellationToken));
                await _db.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO blobs (account_id, sha256, size_bytes, storage_ref)
                    VALUES (@AccountId, @Sha256, @SizeBytes, @StorageRef)
                    ON CONFLICT (account_id, sha256) DO NOTHING
                    """,
                    new { AccountId = accountId, Sha256 = sha256, SizeBytes = sizeBytes, StorageRef = storageRef },
                    transaction: transaction,
                    cancellationToken: cancellationToken));
                await transaction.CommitAsync(cancellationToken);
            }
            catch
            {
                await transaction.RollbackAsync(cancellationToken);
                throw;
            }
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Total committed bytes for the account - the metered quota figure.</summary>
    public async Task<long> GetUsedBytesAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteScalarAsync<long>(new CommandDefinition(
                "SELECT COALESCE(SUM(size_bytes), 0) FROM blobs WHERE account_id = @AccountId",
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

    /// <summary>
    /// The sha256s of sweepable blobs: committed long enough ago (created_at <=
    /// cutoff) and not referenced by a protecting record. A record protects a
    /// blob when it is live, or tombstoned within the grace period (its
    /// client_updated_at is at/after the cutoff), and its payload carries the
    /// blob's content address. A sha256 is an identifier (Safe class,
    /// docs/LOGGING.md), so this is an identity containment check, not a domain
    /// interpretation (hard rule 9).
    /// </summary>
    public async Task<IReadOnlyList<string>> FindOrphanSha256sAsync(
        Guid accountId,
        DateTimeOffset cutoff,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<string>(new CommandDefinition(
                """
                SELECT b.sha256
                FROM blobs b
                WHERE b.account_id = @AccountId
                  AND b.created_at <= @Cutoff
                  AND NOT EXISTS (
                      SELECT 1
                      FROM records r
                      WHERE r.account_id = b.account_id
                        AND (r.deleted = false OR r.client_updated_at >= @Cutoff)
                        AND r.payload::text LIKE '%' || b.sha256 || '%'
                  )
                """,
                new { AccountId = accountId, Cutoff = cutoff },
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

    /// <summary>Deletes blob index rows for the given sha256s.</summary>
    public async Task DeleteBlobsAsync(Guid accountId, IEnumerable<string> sha256s, CancellationToken cancellationToken)
    {
        var list = sha256s.ToList();
        if (list.Count == 0)
        {
            return;
        }

        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM blobs WHERE account_id = @AccountId AND sha256 = ANY(@Sha256s)",
                new { AccountId = accountId, Sha256s = list },
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

    /// <summary>Deletes every blobs row for the account, returning the storage keys removed.</summary>
    public async Task<IReadOnlyList<string>> DeleteAccountBlobsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var keys = (await _db.QueryAsync<string>(new CommandDefinition(
                "SELECT storage_ref FROM blobs WHERE account_id = @AccountId",
                new { AccountId = accountId },
                cancellationToken: cancellationToken))).ToList();

            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM blobs WHERE account_id = @AccountId",
                new { AccountId = accountId },
                cancellationToken: cancellationToken));

            return keys;
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Removes pending rows that are older than the grace period (never-committed begins).</summary>
    public async Task DeleteStalePendingAsync(Guid accountId, DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM blob_pending WHERE account_id = @AccountId AND created_at <= @Cutoff",
                new { AccountId = accountId, Cutoff = cutoff },
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
