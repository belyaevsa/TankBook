using System.Diagnostics;
using System.Text.Json;
using Tankbook.Api.Logging;
using Tankbook.Api.Notifications;

namespace Tankbook.Api.Sync;

/// <summary>The compact per-item log record (docs/LOGGING.md §3 sync.push): ids, outcomes, codes - never values.</summary>
internal sealed record SyncItemLog(
    Guid Id,
    string EntityType,
    int SchemaVersion,
    string Outcome,
    string? ErrorCode = null,
    string? Pointer = null);

/// <summary>
/// Orchestrates push and pull against the record stream (docs/API.md Sync,
/// docs/SYNC.md). The validator and the schema registry are the ones built in
/// P0.9/P4 - this service wires them into the endpoints without re-validating.
/// It logs the sync.push / sync.pull events with ids, counts and outcomes only
/// (hard rule 12: a sync endpoint handling every record in the account is the
/// easiest place in the codebase to leak a payload into a log, so payloads never
/// leave this class as log values).
/// </summary>
public sealed class SyncService
{
    public const int MaxChangesPerBatch = 200; // docs/API.md: <= 200 changes/batch
    public const int MaxPullLimit = 500;       // docs/API.md: default and cap

    private static readonly TimeSpan ClockSkewClamp = TimeSpan.FromHours(24);

    private readonly SyncRepository _repository;
    private readonly PayloadValidator _validator;
    private readonly IPayloadSchemaProvider _schemas;
    private readonly SyncNudgeService _nudge;
    private readonly ILogger<SyncService> _logger;
    private readonly TimeProvider _time;

    public SyncService(
        SyncRepository repository,
        PayloadValidator validator,
        IPayloadSchemaProvider schemas,
        SyncNudgeService nudge,
        ILogger<SyncService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _validator = validator;
        _schemas = schemas;
        _nudge = nudge;
        _logger = logger;
        _time = time;
    }

    public async Task<PushOutcome> PushAsync(
        Guid accountId,
        Guid deviceId,
        IReadOnlyList<PushChange> changes,
        CancellationToken cancellationToken)
    {
        if (!await _repository.IsDeviceActiveAsync(accountId, deviceId, cancellationToken))
        {
            return new PushOutcome(PushStatus.DeviceRevoked, null);
        }

        // Validate every change up front: a schema_version below minSupported is
        // a whole-batch 426 (docs/API.md), so it must be known before any write.
        var validations = new List<PayloadValidationResult>(changes.Count);
        foreach (var change in changes)
        {
            validations.Add(Validate(change));
        }

        if (validations.Any(v => v.Code == PayloadRejectionCode.UpgradeRequired))
        {
            return new PushOutcome(PushStatus.UpgradeRequired, null);
        }

        var stopwatch = Stopwatch.StartNew();
        var results = new List<object>(changes.Count);
        var items = new List<SyncItemLog>(changes.Count);
        var assigned = new List<long>();
        var now = _time.GetUtcNow();

        for (var i = 0; i < changes.Count; i++)
        {
            var change = changes[i];
            var validation = validations[i];

            if (!validation.IsAccepted)
            {
                results.Add(new RejectedPushResult(change.Id, "rejected", validation.WireCode!, validation.Pointer));
                items.Add(new SyncItemLog(change.Id, change.EntityType ?? string.Empty, change.SchemaVersion, "rejected", validation.WireCode, validation.Pointer));
                continue;
            }

            var clientUpdatedAt = ClampClientUpdatedAt(change.ClientUpdatedAt, now, out var clamped);

            var apply = await _repository.ApplyChangeAsync(
                accountId,
                deviceId,
                change.EntityType!,
                change.SchemaVersion,
                change.Id,
                change.BaseScn,
                PayloadText(change),
                clientUpdatedAt,
                change.Deleted,
                cancellationToken);

            if (apply.Status == ApplyStatus.Conflict)
            {
                results.Add(new ConflictPushResult(change.Id, "conflict", apply.Current!));
                items.Add(new SyncItemLog(change.Id, change.EntityType!, change.SchemaVersion, "conflict"));
            }
            else
            {
                assigned.Add(apply.Scn);
                results.Add(new AcceptedPushResult(change.Id, "accepted", apply.Scn, clamped ? true : null));
                items.Add(new SyncItemLog(change.Id, change.EntityType!, change.SchemaVersion, "accepted"));
            }
        }

        stopwatch.Stop();
        var (accepted, conflicts, rejected) = Tally(results);
        TankbookLog.SyncPush(
            _logger,
            changes.Count,
            accepted,
            conflicts,
            rejected,
            assigned.Count == 0 ? null : (assigned.Min(), assigned.Max()),
            stopwatch.Elapsed,
            items);

        // The silent sync nudge (docs/NOTIFICATIONS.md): after a push that wrote
        // at least one record, the account's other devices get a "pull" wakeup.
        // Best-effort and out of band - the service swallows every failure, so a
        // dead provider or a throttled device can never change the push result.
        if (assigned.Count > 0)
        {
            await _nudge.NudgeSiblingsAsync(accountId, deviceId, config: false, cancellationToken);
        }

        return new PushOutcome(PushStatus.Ok, results);
    }

    public async Task<PullOutcome> PullAsync(
        Guid accountId,
        Guid deviceId,
        long since,
        int limit,
        CancellationToken cancellationToken)
    {
        if (!await _repository.IsDeviceActiveAsync(accountId, deviceId, cancellationToken))
        {
            return new PullOutcome(PullStatus.DeviceRevoked, null);
        }

        var stopwatch = Stopwatch.StartNew();
        var records = await _repository.PullAsync(accountId, since, limit, cancellationToken);

        // nextSince is the last SCN actually returned - never a global "max" - so
        // a cursor can never advance past an in-flight commit and skip a record.
        var nextSince = records.Count == 0 ? since : records[^1].Scn;
        var more = records.Count == limit;

        await _repository.UpdateDeviceCursorAsync(deviceId, nextSince, cancellationToken);

        var policy = new SchemaPolicy(PayloadValidator.DefaultMinSupportedVersion, Math.Max(1, _schemas.CurrentVersion));

        stopwatch.Stop();
        TankbookLog.SyncPull(_logger, since, records.Count, nextSince, more, stopwatch.Elapsed);

        return new PullOutcome(PullStatus.Ok, new PullResponse(records, nextSince, more, policy));
    }

    private PayloadValidationResult Validate(PushChange change)
    {
        var payloadJson = change.Payload.ValueKind == JsonValueKind.Undefined
            ? string.Empty
            : change.Payload.GetRawText();
        return _validator.Validate(change.EntityType ?? string.Empty, change.SchemaVersion, payloadJson);
    }

    private static string PayloadText(PushChange change)
        => change.Payload.ValueKind == JsonValueKind.Undefined ? "null" : change.Payload.GetRawText();

    private static DateTimeOffset ClampClientUpdatedAt(DateTimeOffset value, DateTimeOffset now, out bool clamped)
    {
        if (value > now + ClockSkewClamp)
        {
            clamped = true;
            return now;
        }

        clamped = false;
        return value;
    }

    private static (int Accepted, int Conflicts, int Rejected) Tally(IReadOnlyList<object> results)
    {
        var accepted = 0;
        var conflicts = 0;
        var rejected = 0;
        foreach (var result in results)
        {
            switch (result)
            {
                case AcceptedPushResult:
                    accepted++;
                    break;
                case ConflictPushResult:
                    conflicts++;
                    break;
                case RejectedPushResult:
                    rejected++;
                    break;
            }
        }

        return (accepted, conflicts, rejected);
    }
}
