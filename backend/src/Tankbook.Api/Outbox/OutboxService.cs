using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Outbox;

/// <summary>
/// The delivery outbox (migration 016, docs/SECURITY.md "The delivery outbox").
/// A result the gateway computed but could not hand back is queued here for the
/// device that asked for it, drained on the device's next launch, and deleted
/// once collected. The payload is opaque to this service: it is stored and
/// returned byte-for-byte, never read, never queried by meaning - addressed
/// delivery, the same shape as GET /blobs/{sha256}.
///
/// Ack semantics (a written decision, RV.44): the ack is a SEPARATE call, not
/// implicit in the read. Draining returns the rows without deleting them, so a
/// device that dies between read and ack drains the same rows again on its next
/// launch - at-least-once delivery, which is honest. The device dedupes by row
/// id when it persists the inbox item, so a re-delivered row never becomes a
/// second item; the ack then deletes the row and it is never delivered again.
/// </summary>
public sealed class OutboxService
{
    private readonly OutboxRepository _repository;
    private readonly OutboxOptions _options;
    private readonly ILogger<OutboxService> _logger;
    private readonly TimeProvider _time;

    public OutboxService(
        OutboxRepository repository,
        IOptions<OutboxOptions> options,
        ILogger<OutboxService> logger,
        TimeProvider time)
    {
        _repository = repository;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    /// <summary>Queues one opaque payload for the device. Logs shape only (counts/ids, never the payload - hard rule 12).</summary>
    public async Task EnqueueAsync(Guid accountId, Guid deviceId, byte[] payload, CancellationToken cancellationToken)
    {
        await _repository.InsertAsync(Guid.NewGuid(), accountId, deviceId, payload, cancellationToken);
        TankbookLog.OutboxEnqueue(_logger, accountId, deviceId, payload.Length);
    }

    /// <summary>The device's pending rows, oldest first. Read-only: the ack is <see cref="AckAsync"/>.</summary>
    public async Task<IReadOnlyList<OutboxRow>> DrainAsync(Guid accountId, Guid deviceId, CancellationToken cancellationToken)
    {
        var rows = await _repository.ListForDeviceAsync(accountId, deviceId, cancellationToken);
        if (rows.Count > 0)
        {
            TankbookLog.OutboxDrain(_logger, accountId, deviceId, rows.Count);
        }

        return rows;
    }

    /// <summary>Deletes a collected row, scoped to its owner device. Idempotent - a foreign or already-collected id deletes nothing and is not an error.</summary>
    public Task<int> AckAsync(Guid accountId, Guid deviceId, Guid id, CancellationToken cancellationToken)
        => _repository.DeleteAsync(accountId, deviceId, id, cancellationToken);

    /// <summary>
    /// One retention pass: rows past the 30-day cutoff are deleted. Both sides
    /// of the cutoff are asserted by the L2 test - a retention promise with no
    /// test is a promise that quietly stops being true.
    /// </summary>
    public async Task<int> PurgeDueAsync(CancellationToken cancellationToken)
    {
        var cutoff = _time.GetUtcNow() - _options.RetentionPeriod;
        var due = await _repository.ListDueAsync(cutoff, cancellationToken);
        if (due.Count == 0)
        {
            return 0;
        }

        var deleted = await _repository.DeleteManyAsync(due.Select(r => r.Id).ToList(), cancellationToken);
        TankbookLog.OutboxPurge(_logger, deleted);
        return deleted;
    }

    /// <summary>Deletes every row an account owns (docs/SECURITY.md: deleting the account deletes these too).</summary>
    public async Task<int> PurgeAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var deleted = await _repository.PurgeAccountAsync(accountId, cancellationToken);
        if (deleted > 0)
        {
            TankbookLog.OutboxPurge(_logger, deleted);
        }

        return deleted;
    }
}
