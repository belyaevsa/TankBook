using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Auth;

/// <summary>One refresh-token row (migration 004).</summary>
public sealed class RefreshTokenRow
{
    public Guid Id { get; set; }

    public Guid AccountId { get; set; }

    public Guid DeviceId { get; set; }

    public string TokenHash { get; set; } = string.Empty;

    public Guid ChainId { get; set; }

    public DateTimeOffset IssuedAt { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }

    public DateTimeOffset? RotatedAt { get; set; }

    public DateTimeOffset? RevokedAt { get; set; }

    public Guid? ReplacedBy { get; set; }
}

/// <summary>What a refresh-token presentation resolved to.</summary>
public enum RefreshRotationOutcome
{
    Rotated,
    NotFound,
    AlreadyRevoked,
    ReuseDetected,
    Expired,
}

/// <summary>The identity behind a refresh rotation, for minting the new access token.</summary>
public sealed record RefreshRotationResult(
    RefreshRotationOutcome Outcome,
    Guid? AccountId,
    Guid? DeviceId,
    Guid? ChainId);

/// <summary>
/// Database access for accounts, devices, and refresh tokens (migrations 001 and
/// 004). The find-or-create path agrees with the unique constraints under real
/// concurrency: it inserts with ON CONFLICT DO NOTHING and re-selects the winner
/// when the constraint refused, so concurrent first sign-ins for one subject
/// produce exactly one account.
/// </summary>
public sealed class AuthRepository
{
    private const string RefreshColumns = """
        SELECT id          AS Id,
               account_id  AS AccountId,
               device_id   AS DeviceId,
               token_hash  AS TokenHash,
               chain_id    AS ChainId,
               issued_at   AS IssuedAt,
               expires_at  AS ExpiresAt,
               rotated_at  AS RotatedAt,
               revoked_at  AS RevokedAt,
               replaced_by AS ReplacedBy
        FROM refresh_tokens
        """;

    private readonly IDbConnection _db;

    public AuthRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>
    /// Finds the account for the verified subject, or creates it. Returns the
    /// account id, whether this call created the account, and the account's
    /// stored email (the column set at creation, never refreshed - the verified
    /// id token's email is a first-sight value, not a rolling override).
    /// Race-safe: a concurrent create for the same subject loses the insert (ON
    /// CONFLICT DO NOTHING) and re-selects the winner.
    /// </summary>
    public async Task<(Guid AccountId, bool Created, string Email)> FindOrCreateAccountAsync(
        string provider,
        string subject,
        string email,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var insertSql = provider == "apple"
                ? "INSERT INTO accounts (id, apple_sub, google_sub, email) VALUES (@Id, @Sub, NULL, @Email) ON CONFLICT (apple_sub) DO NOTHING RETURNING id"
                : "INSERT INTO accounts (id, apple_sub, google_sub, email) VALUES (@Id, NULL, @Sub, @Email) ON CONFLICT (google_sub) DO NOTHING RETURNING id";

            var inserted = await _db.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
                insertSql,
                new { Id = Guid.NewGuid(), Sub = subject, Email = email },
                cancellationToken: cancellationToken));

            if (inserted is not null)
            {
                return (inserted.Value, true, email);
            }

            var selectSql = provider == "apple"
                ? "SELECT id, email FROM accounts WHERE apple_sub = @Sub"
                : "SELECT id, email FROM accounts WHERE google_sub = @Sub";
            var existing = await _db.QuerySingleAsync<(Guid Id, string Email)>(new CommandDefinition(
                selectSql,
                new { Sub = subject },
                cancellationToken: cancellationToken));
            return (existing.Id, false, existing.Email);
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
    /// Reuses the caller's device row when it already belongs to this account,
    /// and mints a fresh one otherwise (docs/API.md POST /auth/session). The
    /// reuse is bound to the account: a device id that belongs to a different
    /// account matches the UPDATE's WHERE and returns nothing, so the caller
    /// can never adopt another account's row. A revoked row that its device
    /// returns is re-attached (revoked_at cleared) - the owner proved the
    /// account again by presenting a valid id token.
    /// </summary>
    public async Task<Guid> FindOrCreateDeviceAsync(
        Guid accountId,
        Guid? deviceId,
        string name,
        string platform,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            if (deviceId is not null)
            {
                var reused = await _db.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
                    """
                    UPDATE devices
                    SET name = @Name, platform = @Platform, last_seen_at = now(), revoked_at = NULL
                    WHERE id = @DeviceId AND account_id = @AccountId
                    RETURNING id
                    """,
                    new { DeviceId = deviceId.Value, AccountId = accountId, Name = name, Platform = platform },
                    cancellationToken: cancellationToken));

                if (reused is not null)
                {
                    return reused.Value;
                }
            }

            var id = Guid.NewGuid();
            await _db.ExecuteAsync(new CommandDefinition(
                "INSERT INTO devices (id, account_id, name, platform) VALUES (@Id, @AccountId, @Name, @Platform)",
                new { Id = id, AccountId = accountId, Name = name, Platform = platform },
                cancellationToken: cancellationToken));
            return id;
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Inserts a fresh refresh token as the start of a new chain.</summary>
    public async Task InsertRefreshTokenAsync(
        Guid id,
        Guid accountId,
        Guid deviceId,
        string tokenHash,
        Guid chainId,
        DateTimeOffset now,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO refresh_tokens (id, account_id, device_id, token_hash, chain_id, issued_at, expires_at)
                VALUES (@Id, @AccountId, @DeviceId, @TokenHash, @ChainId, @Now, @ExpiresAt)
                """,
                new
                {
                    Id = id,
                    AccountId = accountId,
                    DeviceId = deviceId,
                    TokenHash = tokenHash,
                    ChainId = chainId,
                    Now = now,
                    ExpiresAt = expiresAt,
                },
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
    /// Rotates a refresh token atomically (docs/API.md POST /auth/refresh). The
    /// presented token's row is locked FOR UPDATE so concurrent presentations of
    /// the same token serialize. Reuse - a token whose rotated_at is already set
    /// - revokes the entire chain in the same transaction.
    /// </summary>
    public async Task<RefreshRotationResult> RotateAsync(
        string presentedHash,
        Guid newTokenId,
        string newTokenHash,
        DateTimeOffset now,
        DateTimeOffset newExpiresAt,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var connection = (DbConnection)_db;
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                var row = await _db.QuerySingleOrDefaultAsync<RefreshTokenRow>(new CommandDefinition(
                    RefreshColumns + " WHERE token_hash = @Hash FOR UPDATE",
                    new { Hash = presentedHash },
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                if (row is null)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new RefreshRotationResult(RefreshRotationOutcome.NotFound, null, null, null);
                }

                if (row.RevokedAt is not null)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new RefreshRotationResult(RefreshRotationOutcome.AlreadyRevoked, null, null, null);
                }

                if (row.RotatedAt is not null)
                {
                    // Reuse of a rotated token: revoke the whole chain (theft signal).
                    await _db.ExecuteAsync(new CommandDefinition(
                        "UPDATE refresh_tokens SET revoked_at = @Now WHERE chain_id = @ChainId AND revoked_at IS NULL",
                        new { Now = now, ChainId = row.ChainId },
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                    await transaction.CommitAsync(cancellationToken);
                    return new RefreshRotationResult(RefreshRotationOutcome.ReuseDetected, row.AccountId, row.DeviceId, row.ChainId);
                }

                if (row.ExpiresAt <= now)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new RefreshRotationResult(RefreshRotationOutcome.Expired, null, null, null);
                }

                await _db.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO refresh_tokens (id, account_id, device_id, token_hash, chain_id, issued_at, expires_at)
                    VALUES (@NewId, @AccountId, @DeviceId, @NewHash, @ChainId, @Now, @NewExpiresAt)
                    """,
                    new
                    {
                        NewId = newTokenId,
                        row.AccountId,
                        row.DeviceId,
                        NewHash = newTokenHash,
                        row.ChainId,
                        Now = now,
                        NewExpiresAt = newExpiresAt,
                    },
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                await _db.ExecuteAsync(new CommandDefinition(
                    "UPDATE refresh_tokens SET rotated_at = @Now, replaced_by = @NewId WHERE id = @OldId",
                    new { Now = now, NewId = newTokenId, OldId = row.Id },
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                await transaction.CommitAsync(cancellationToken);
                return new RefreshRotationResult(RefreshRotationOutcome.Rotated, row.AccountId, row.DeviceId, row.ChainId);
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

    /// <summary>
    /// Revokes every refresh chain belonging to an account (docs/API.md
    /// DELETE /account). After account deletion every device must stop refreshing
    /// too, not just stop syncing; this revokes all of them in one statement.
    /// Deletes nothing - the refresh-token rows remain, marked revoked.
    /// </summary>
    public async Task RevokeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE refresh_tokens SET revoked_at = now() WHERE account_id = @AccountId AND revoked_at IS NULL",
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
    /// Revokes every refresh chain belonging to a device (docs/API.md
    /// DELETE /auth/session). Deletes nothing - local data stays local.
    /// </summary>
    public async Task RevokeDeviceAsync(Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE refresh_tokens SET revoked_at = now() WHERE device_id = @DeviceId AND revoked_at IS NULL",
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
