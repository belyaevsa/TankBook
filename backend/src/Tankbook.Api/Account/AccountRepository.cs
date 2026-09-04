using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Account;

/// <summary>A devices row read for the "manage devices" screen (migrations 001/005).</summary>
public sealed record DeviceRow(Guid Id, string Name, string Platform, DateTime LastSeenAt, bool Revoked);

/// <summary>A tombstoned account eligible for purge (RV.63: the accountHash is computed from the id, not the email).</summary>
public sealed record DueAccountRow(Guid Id, string Email, DateTime DeletedAt);

/// <summary>The result of a tombstone attempt: the account's email and deletion stamp, and whether this call set it.</summary>
public sealed record TombstoneRow(string Email, DateTimeOffset DeletedAt, bool TombstonedNow);

/// <summary>
/// Database access for the account & devices surface (docs/API.md "Account &
/// devices") and the grace purge job (docs/SYNC.md). Device management operates
/// on ownership (account_id) only - a device id belonging to another account is
/// indistinguishable from absence, so the endpoints answer 404 rather than 403
/// and no information leaks (the same principle the blob endpoints use).
/// </summary>
public sealed class AccountRepository
{
    private readonly IDbConnection _db;

    public AccountRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>This account's devices with lastSeenAt and the revoked flag, most recently seen first.</summary>
    public async Task<IReadOnlyList<AccountDevice>> ListDevicesAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<DeviceRow>(new CommandDefinition(
                """
                SELECT id, name, platform, last_seen_at AS LastSeenAt, revoked_at IS NOT NULL AS Revoked
                FROM devices
                WHERE account_id = @AccountId
                ORDER BY last_seen_at DESC
                """,
                new { AccountId = accountId },
                cancellationToken: cancellationToken));

            return rows.Select(row => new AccountDevice(
                row.Id,
                row.Name,
                row.Platform,
                ToOffset(row.LastSeenAt),
                row.Revoked)).ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>True when the device exists and belongs to this account (cross-account ids are indistinguishable from absence).</summary>
    public async Task<bool> DeviceBelongsToAccountAsync(Guid accountId, Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleAsync<bool>(new CommandDefinition(
                """
                SELECT EXISTS (
                    SELECT 1 FROM devices WHERE id = @DeviceId AND account_id = @AccountId
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

    /// <summary>Stores the push token (null empties the row - APNs invalidation falls back to polling).</summary>
    public async Task SetPushTokenAsync(Guid deviceId, string? token, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE devices SET push_token = @Token WHERE id = @DeviceId",
                new { DeviceId = deviceId, Token = token },
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

    /// <summary>Sets the device revocation marker (next pull gets 410 via the existing IsDeviceActiveAsync check).</summary>
    public async Task MarkDeviceRevokedAsync(Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE devices SET revoked_at = now() WHERE id = @DeviceId AND revoked_at IS NULL",
                new { DeviceId = deviceId },
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
    /// Tombstones the account (docs/SYNC.md: purge after grace, nothing deleted
    /// now). Idempotent: a second call returns the existing stamp with
    /// TombstonedNow false. Returns null when the account row is gone (already
    /// purged).
    /// </summary>
    public async Task<TombstoneRow?> TombstoneAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var row = await _db.QuerySingleOrDefaultAsync<(string Email, DateTime DeletedAt)>(new CommandDefinition(
                """
                UPDATE accounts SET deleted_at = now()
                WHERE id = @AccountId AND deleted_at IS NULL
                RETURNING email, deleted_at
                """,
                new { AccountId = accountId },
                cancellationToken: cancellationToken));

            if (row != default)
            {
                return new TombstoneRow(row.Email, ToOffset(row.DeletedAt), TombstonedNow: true);
            }

            var existing = await _db.QuerySingleOrDefaultAsync<(string Email, DateTime DeletedAt)>(new CommandDefinition(
                "SELECT email, deleted_at FROM accounts WHERE id = @AccountId",
                new { AccountId = accountId },
                cancellationToken: cancellationToken));

            return existing == default
                ? null
                : new TombstoneRow(existing.Email, ToOffset(existing.DeletedAt), TombstonedNow: false);
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Tombstoned accounts whose grace period has elapsed (the purge job's working set).</summary>
    public async Task<IReadOnlyList<DueAccountRow>> ListDueAccountsAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<DueAccountRow>(new CommandDefinition(
                """
                SELECT id AS Id, email AS Email, deleted_at AS DeletedAt
                FROM accounts
                WHERE deleted_at IS NOT NULL AND deleted_at <= @Cutoff
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

    /// <summary>How many records the account still holds (for the account.delete log's recordsPurged).</summary>
    public async Task<long> CountRecordsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.ExecuteScalarAsync<long>(new CommandDefinition(
                "SELECT count(*) FROM records WHERE account_id = @AccountId",
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
    /// Deletes the account row; the ON DELETE CASCADE foreign keys remove the
    /// records, devices, SCN allocator, blob index, refresh tokens, feedback and
    /// LLM usage in the same statement (docs/SYNC.md: the purge deletes
    /// everything, after the grace period).
    /// </summary>
    public async Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM accounts WHERE id = @AccountId",
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

    private static DateTimeOffset ToOffset(DateTime value)
        => new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

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
