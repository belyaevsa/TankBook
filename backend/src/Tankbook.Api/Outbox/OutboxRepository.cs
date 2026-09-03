using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Outbox;

/// <summary>One queued delivery, as the drain returns it (id + opaque payload bytes).</summary>
public sealed record OutboxRow(Guid Id, byte[] Payload);

/// <summary>
/// Database access for the delivery outbox (migration 016, docs/SECURITY.md
/// "The delivery outbox"). The gateway writes one row when it cannot hand an
/// answer back; the device drains its own rows and acks them. The payload is
/// OPAQUE BYTES: no query here reads a field, and there is no search or stats
/// over it - only addressed retrieval (id + payload, by account + device), the
/// same shape as GET /blobs/{sha256}.
/// </summary>
public sealed class OutboxRepository
{
    private readonly IDbConnection _db;

    public OutboxRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>Queues one opaque payload for the device that asked for it.</summary>
    public async Task InsertAsync(Guid id, Guid accountId, Guid deviceId, byte[] payload, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO delivery_outbox (id, account_id, device_id, payload)
                VALUES (@Id, @AccountId, @DeviceId, @Payload)
                """,
                new { Id = id, AccountId = accountId, DeviceId = deviceId, Payload = payload },
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
    /// The device's pending rows, oldest first. A DRAIN does not delete - the
    /// ack is a separate call, so a device that dies between read and ack sees
    /// the same rows again (at-least-once; the device dedupes by id). The
    /// payload is returned byte-for-byte, never read.
    /// </summary>
    public async Task<IReadOnlyList<OutboxRow>> ListForDeviceAsync(Guid accountId, Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<OutboxRow>(new CommandDefinition(
                """
                SELECT id AS Id, payload AS Payload
                FROM delivery_outbox
                WHERE account_id = @AccountId AND device_id = @DeviceId
                ORDER BY created_at, id
                """,
                new { AccountId = accountId, DeviceId = deviceId },
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
    /// Deletes a collected row (the ack), scoped to the account and device that
    /// own it - a foreign id is indistinguishable from absence and deletes
    /// nothing (no existence leak, the blob/import 404 principle). Returns the
    /// number of rows deleted (0 or 1).
    /// </summary>
    public async Task<int> DeleteAsync(Guid accountId, Guid deviceId, Guid id, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                """
                DELETE FROM delivery_outbox
                WHERE id = @Id AND account_id = @AccountId AND device_id = @DeviceId
                """,
                new { Id = id, AccountId = accountId, DeviceId = deviceId },
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

    /// <summary>Rows past the retention cutoff (the purge job's working set; id + account only, never a payload).</summary>
    public async Task<IReadOnlyList<(Guid Id, Guid AccountId)>> ListDueAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<(Guid Id, Guid AccountId)>(new CommandDefinition(
                """
                SELECT id AS Id, account_id AS AccountId
                FROM delivery_outbox
                WHERE created_at <= @Cutoff
                """,
                new { Cutoff = cutoff },
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

    /// <summary>Deletes the given rows (retention purge). Never reads a payload.</summary>
    public async Task<int> DeleteManyAsync(IReadOnlyList<Guid> ids, CancellationToken cancellationToken)
    {
        if (ids.Count == 0)
        {
            return 0;
        }

        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM delivery_outbox WHERE id = ANY(@Ids)",
                new { Ids = ids.ToArray() },
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

    /// <summary>Deletes every row an account owns (account-deletion purge; also covered by the cascade FK).</summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM delivery_outbox WHERE account_id = @AccountId",
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
