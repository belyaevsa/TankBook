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
/// A change that passed validation and is queued for the batch apply (RV.105).
/// <see cref="Index"/> is its position in the request, so per-change results can
/// be placed back in wire order after the single repository call.
/// </summary>
internal sealed record PendingApply(
    int Index,
    Guid Id,
    string EntityType,
    int SchemaVersion,
    long BaseScn,
    string PayloadJson,
    DateTimeOffset ClientUpdatedAt,
    bool Deleted,
    bool Clamped);

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
        var results = new object[changes.Count];
        var items = new SyncItemLog[changes.Count];
        var assigned = new List<long>(changes.Count);
        var now = _time.GetUtcNow();

        // Phase 1 (pure): validation outcomes and clock clamps. Rejected changes
        // are settled here; the rest queue for one batched apply (RV.105).
        var pending = new List<PendingApply>(changes.Count);
        for (var i = 0; i < changes.Count; i++)
        {
            var change = changes[i];
            var validation = validations[i];

            if (!validation.IsAccepted)
            {
                results[i] = new RejectedPushResult(change.Id, "rejected", validation.WireCode!, validation.Pointer);
                items[i] = new SyncItemLog(change.Id, change.EntityType ?? string.Empty, change.SchemaVersion, "rejected", validation.WireCode, validation.Pointer);
                continue;
            }

            var clientUpdatedAt = ClampClientUpdatedAt(change.ClientUpdatedAt, now, out var clamped);
            pending.Add(new PendingApply(
                i,
                change.Id,
                change.EntityType!,
                change.SchemaVersion,
                change.BaseScn,
                PayloadText(change),
                clientUpdatedAt,
                change.Deleted,
                clamped));
        }

        // Phase 2 (one DB transaction for the whole batch, RV.105 2026-09-07):
        // per-record transactions cost a fixed ~578 ms each on the production host
        // (the commit's fsync), so 200 records were ~115 s against the client's
        // 120 s upload budget. One commit per batch collapses that. A conflict or
        // an idempotent replay is a no-op inside the transaction, never a
        // rollback, so partial acceptance survives (docs/SYNC.md).
        var commits = 0;
        if (pending.Count > 0)
        {
            var batch = new BatchChange[pending.Count];
            for (var i = 0; i < pending.Count; i++)
            {
                var p = pending[i];
                batch[i] = new BatchChange(p.Id, p.EntityType, p.SchemaVersion, p.BaseScn, p.PayloadJson, p.ClientUpdatedAt, p.Deleted);
            }

            var applied = await _repository.ApplyBatchAsync(accountId, deviceId, batch, cancellationToken);
            commits = applied.Commits;
            for (var i = 0; i < pending.Count; i++)
            {
                var p = pending[i];
                var apply = applied.Results[i];
                if (apply.Status == ApplyStatus.Conflict)
                {
                    results[p.Index] = new ConflictPushResult(p.Id, "conflict", apply.Current!);
                    items[p.Index] = new SyncItemLog(p.Id, p.EntityType, p.SchemaVersion, "conflict");
                }
                else
                {
                    assigned.Add(apply.Scn);
                    results[p.Index] = new AcceptedPushResult(p.Id, "accepted", apply.Scn, p.Clamped ? true : null);
                    items[p.Index] = new SyncItemLog(p.Id, p.EntityType, p.SchemaVersion, "accepted");
                }
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
            commits,
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
