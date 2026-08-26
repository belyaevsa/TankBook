using System.Diagnostics;
using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Notifications;

/// <summary>
/// Orchestrates the silent sync nudge (docs/NOTIFICATIONS.md): after one device
/// pushes, its siblings get a silent "pull" so they converge in seconds rather
/// than the next poll. Every rule the doc pins lives here:
/// <list type="bullet">
/// <item>best-effort and out of band - a failed nudge never touches the push result (hard rule "never a dependency");</item>
/// <item>throttled server-side - one nudge per device per window, bursts collapse via an atomic claim;</item>
/// <item>the pusher is never nudged - it already has the data;</item>
/// <item>a dead token clears the row (fall back to polling), a transient failure does not.</item>
/// </list>
/// The service swallows everything: it is called from the push path and must
/// never turn a deliverable push into an error.
/// </summary>
public sealed class SyncNudgeService
{
    private readonly NudgeRepository _repository;
    private readonly IApnsClient _apns;
    private readonly NudgeOptions _options;
    private readonly ILogger<SyncNudgeService> _logger;
    private readonly TimeProvider _time;

    public SyncNudgeService(
        NudgeRepository repository,
        IApnsClient apns,
        IOptions<NudgeOptions> options,
        ILogger<SyncNudgeService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _apns = apns;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    /// <summary>
    /// Nudges every sibling of <paramref name="pusherDeviceId"/> that is due.
    /// <paramref name="config"/> marks a config nudge (docs/CONFIG.md) rather
    /// than a plain sync nudge; nothing sets it today - the flag is wired for
    /// the urgent-change path, not built into a detector.
    /// </summary>
    public async Task NudgeSiblingsAsync(
        Guid accountId,
        Guid pusherDeviceId,
        bool config,
        CancellationToken cancellationToken)
    {
        var targets = await _repository.ListSiblingTargetsAsync(accountId, pusherDeviceId, cancellationToken);
        if (targets.Count == 0)
        {
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        var now = _time.GetUtcNow();
        var cutoff = now - _options.ThrottleWindow;
        var delivered = 0;
        var invalidToken = 0;
        var transient = 0;
        var throttled = 0;

        foreach (var target in targets)
        {
            if (!await _repository.TryClaimSlotAsync(target.DeviceId, now, cutoff, cancellationToken))
            {
                throttled++;
                continue;
            }

            var result = await SendAsync(target.PushToken, config, cancellationToken);
            switch (result.Outcome)
            {
                case ApnsOutcome.Delivered:
                    delivered++;
                    break;
                case ApnsOutcome.InvalidToken:
                    invalidToken++;
                    await _repository.ClearPushTokenAsync(target.DeviceId, cancellationToken);
                    break;
                default:
                    transient++;
                    break;
            }
        }

        stopwatch.Stop();
        TankbookLog.SyncNudge(
            _logger,
            accountId,
            targets.Count,
            delivered,
            invalidToken,
            transient,
            throttled,
            config,
            stopwatch.Elapsed);
    }

    private async Task<ApnsSendResult> SendAsync(string token, bool config, CancellationToken cancellationToken)
    {
        try
        {
            return await _apns.SendAsync(token, ApnsPayload.Silent(config), cancellationToken);
        }
        catch (Exception ex)
        {
            // The client contract says it never throws, but the push path must
            // survive a double that does anyway (hard rule: failure is never fatal).
            _logger.LogWarning(
                "sync.nudge transport threw: {ExceptionType}",
                ex.GetType().Name);
            return new ApnsSendResult(ApnsOutcome.TransientFailure, ex.GetType().Name);
        }
    }
}
