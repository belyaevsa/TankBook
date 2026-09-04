namespace Tankbook.Api.Llm;

/// <summary>
/// LLM call-ledger configuration (docs/SECURITY.md "LLM call ledger" and "The
/// ledger write queue"). Bound from the "LlmCalls" configuration section;
/// environment variables use the LlmCalls__RetentionDays,
/// LlmCalls__PurgeIntervalMinutes, LlmCalls__RetryIntervalMinutes and
/// LlmCalls__MaxRetryAttempts form.
/// </summary>
public sealed class LlmCallOptions
{
    public const string SectionName = "LlmCalls";

    /// <summary>
    /// How long the ledger's content (prompt/response/thinking bodies and the
    /// prompt rendition blob) is retained before the purge job removes it. The
    /// row itself survives - it is the spend ledger, and only the user content
    /// it carried is dropped. 30 days matches the tombstone/undo window and the
    /// import-file retention, so one number governs "how long can I get it back"
    /// (docs/SECURITY.md - a written commitment, not an implementation detail).
    /// </summary>
    public int RetentionDays { get; set; } = 30;

    /// <summary>How often the background purge job runs a pass. Hourly by default.</summary>
    public int PurgeIntervalMinutes { get; set; } = 60;

    /// <summary>
    /// The base interval of the ledger write queue's retry pass (RV.53), and the
    /// first backoff step. A row that could not be inserted synchronously is
    /// retried this soon, then at doubling intervals up to the give-up bound.
    /// </summary>
    public int RetryIntervalMinutes { get; set; } = 10;

    /// <summary>
    /// How many times the retry pass attempts a queued ledger row before giving
    /// up. The give-up is a defined outcome (docs/SECURITY.md "The ledger write
    /// queue"): the row is dropped and a shape-only Warning names the loss -
    /// never an infinite retry, and never a failure surfaced to the user whose
    /// paid call it records.
    /// </summary>
    public int MaxRetryAttempts { get; set; } = 6;

    public TimeSpan RetentionPeriod => TimeSpan.FromDays(RetentionDays);

    public TimeSpan PurgeInterval => TimeSpan.FromMinutes(PurgeIntervalMinutes);

    public TimeSpan RetryInterval => TimeSpan.FromMinutes(RetryIntervalMinutes);
}
