namespace Tankbook.Api.Outbox;

/// <summary>
/// Delivery-outbox configuration (docs/SECURITY.md "The delivery outbox").
/// Bound from the "DeliveryOutbox" configuration section; environment
/// variables use the DeliveryOutbox__RetentionDays and
/// DeliveryOutbox__PurgeIntervalMinutes form. Retention is the one number that
/// already governs the tombstone/undo window, /import/parse's file and the call
/// ledger's content - 30 days (docs/SECURITY.md - a written commitment, not an
/// implementation detail).
/// </summary>
public sealed class OutboxOptions
{
    public const string SectionName = "DeliveryOutbox";

    /// <summary>
    /// How long a queued result is retained before the purge job removes it. 30
    /// days matches the tombstone/undo window, /import/parse's file and the call
    /// ledger's content, so one number governs "how long can I get it back".
    /// </summary>
    public int RetentionDays { get; set; } = 30;

    /// <summary>How often the background purge job runs a pass. Hourly by default.</summary>
    public int PurgeIntervalMinutes { get; set; } = 60;

    public TimeSpan RetentionPeriod => TimeSpan.FromDays(RetentionDays);

    public TimeSpan PurgeInterval => TimeSpan.FromMinutes(PurgeIntervalMinutes);
}
