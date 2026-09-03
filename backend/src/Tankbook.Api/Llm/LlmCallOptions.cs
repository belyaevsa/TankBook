namespace Tankbook.Api.Llm;

/// <summary>
/// LLM call-ledger configuration (docs/SECURITY.md "LLM call ledger"). Bound
/// from the "LlmCalls" configuration section; environment variables use the
/// LlmCalls__RetentionDays, LlmCalls__PurgeIntervalMinutes form.
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

    public TimeSpan RetentionPeriod => TimeSpan.FromDays(RetentionDays);

    public TimeSpan PurgeInterval => TimeSpan.FromMinutes(PurgeIntervalMinutes);
}
