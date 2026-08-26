using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Notifications;

/// <summary>A sibling device that can be nudged: its id and its push token (never logged - hard rule 12).</summary>
public sealed record NudgeTarget(Guid DeviceId, string PushToken);

/// <summary>
/// Database access for the sync nudge (docs/NOTIFICATIONS.md). Three queries:
/// who to nudge (the account's other live devices with a token), the atomic
/// throttle claim, and clearing a dead token. The claim is a conditional UPDATE
/// keyed by primary key - a row locks under concurrent pushes, so ten pushes in
/// a burst produce exactly one winner per device and the rest collapse.
/// </summary>
public sealed class NudgeRepository
{
    private readonly IDbConnection _db;

    public NudgeRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>
    /// The pusher's sibling devices that are still live and hold a token. The
    /// pusher itself is always excluded - it already has the data, so nudging it
    /// is a wakeup that buys nothing.
    /// </summary>
    public async Task<IReadOnlyList<NudgeTarget>> ListSiblingTargetsAsync(
        Guid accountId,
        Guid pusherDeviceId,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<(Guid Id, string PushToken)>(new CommandDefinition(
                """
                SELECT id, push_token
                FROM devices
                WHERE account_id = @AccountId
                  AND id <> @PusherDeviceId
                  AND push_token IS NOT NULL
                  AND revoked_at IS NULL
                """,
                new { AccountId = accountId, PusherDeviceId = pusherDeviceId },
                cancellationToken: cancellationToken));

            return rows.Select(r => new NudgeTarget(r.Id, r.PushToken)).ToList();
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
    /// Atomically claims the throttle slot for one device: succeeds only when the
    /// device was never nudged or its last nudge is at or before <paramref name="cutoff"/>.
    /// The winner's stamp is the injected clock, so the window is driven by
    /// TimeProvider and is testable without sleeping.
    /// </summary>
    public async Task<bool> TryClaimSlotAsync(
        Guid deviceId,
        DateTimeOffset now,
        DateTimeOffset cutoff,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var affected = await _db.ExecuteAsync(new CommandDefinition(
                """
                UPDATE devices
                SET last_nudged_at = @Now
                WHERE id = @DeviceId
                  AND push_token IS NOT NULL
                  AND (last_nudged_at IS NULL OR last_nudged_at <= @Cutoff)
                """,
                new { DeviceId = deviceId, Now = now, Cutoff = cutoff },
                cancellationToken: cancellationToken));

            return affected == 1;
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Clears the push token after APNs reports it dead; the device silently falls back to polling.</summary>
    public async Task ClearPushTokenAsync(Guid deviceId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE devices SET push_token = NULL WHERE id = @DeviceId",
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
