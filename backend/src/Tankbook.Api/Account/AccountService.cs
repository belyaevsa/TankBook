using Microsoft.Extensions.Options;
using Tankbook.Api.Auth;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Account;

/// <summary>
/// Orchestrates the account & devices surface (docs/API.md "Account & devices",
/// docs/SYNC.md "Offline & failure behavior"). Device revocation reuses P4.1's
/// refresh-chain revocation (AuthRepository.RevokeDeviceAsync) - the device
/// marker and the chain revocation are the same two writes a revoked device has
/// always needed, now reached by the DELETE /account/devices/{id} route.
/// Account deletion is a tombstone: it sets accounts.deleted_at and revokes every
/// refresh chain, and deletes nothing - the purge job clears the data after the
/// grace period, so local data stays local.
/// </summary>
public sealed class AccountService
{
    private readonly AccountRepository _repository;
    private readonly AuthRepository _authRepository;
    private readonly AccountOptions _options;
    private readonly LoggingOptions _loggingOptions;
    private readonly ILogger<AccountService> _logger;
    private readonly TimeProvider _time;

    public AccountService(
        AccountRepository repository,
        AuthRepository authRepository,
        IOptions<AccountOptions> options,
        LoggingOptions loggingOptions,
        ILogger<AccountService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _authRepository = authRepository;
        _options = options.Value;
        _loggingOptions = loggingOptions;
        _logger = logger;
        _time = time;
    }

    public Task<IReadOnlyList<AccountDevice>> GetDevicesAsync(Guid accountId, CancellationToken cancellationToken)
        => _repository.ListDevicesAsync(accountId, cancellationToken);

    /// <summary>Stores or clears a device's push token; a foreign device id is indistinguishable from absence (404).</summary>
    public async Task<PushTokenStatus> SetPushTokenAsync(
        Guid accountId,
        Guid deviceId,
        string? token,
        CancellationToken cancellationToken)
    {
        if (!await _repository.DeviceBelongsToAccountAsync(accountId, deviceId, cancellationToken))
        {
            return PushTokenStatus.NotFound;
        }

        await _repository.SetPushTokenAsync(deviceId, token, cancellationToken);
        return PushTokenStatus.Stored;
    }

    /// <summary>
    /// Revokes one device: marks it revoked (next pull 410) and revokes its
    /// refresh chains. Other devices and every record are untouched.
    /// </summary>
    public async Task<RevokeDeviceStatus> RevokeDeviceAsync(
        Guid accountId,
        Guid deviceId,
        CancellationToken cancellationToken)
    {
        if (!await _repository.DeviceBelongsToAccountAsync(accountId, deviceId, cancellationToken))
        {
            return RevokeDeviceStatus.NotFound;
        }

        await _repository.MarkDeviceRevokedAsync(deviceId, cancellationToken);
        await _authRepository.RevokeDeviceAsync(deviceId, cancellationToken);
        return RevokeDeviceStatus.Revoked;
    }

    /// <summary>
    /// Tombstones the account (docs/SYNC.md): sets accounts.deleted_at, revokes
    /// every refresh chain so devices stop refreshing, and schedules the purge.
    /// Deletes no records synchronously - the grace period is the whole point.
    /// Idempotent; the account.delete log fires only on the first tombstone.
    /// </summary>
    public async Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var row = await _repository.TombstoneAccountAsync(accountId, cancellationToken);
        if (row is null)
        {
            return;
        }

        await _authRepository.RevokeAccountAsync(accountId, cancellationToken);

        if (row.TombstonedNow)
        {
            var accountHash = AccountHash.Compute(row.Email, _loggingOptions.HashSalt);
            var graceEndsAt = row.DeletedAt + _options.DeletionGracePeriod;
            TankbookLog.AccountDelete(_logger, accountHash, recordsPurged: 0, blobsPurged: 0, graceEndsAt);
        }
    }
}
