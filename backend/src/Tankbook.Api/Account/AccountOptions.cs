namespace Tankbook.Api.Account;

/// <summary>
/// Account-lifecycle configuration (docs/API.md "Account & devices", docs/SYNC.md
/// "Offline & failure behavior"). Bound from the "Account" configuration section;
/// environment variables use the Account__DeletionGraceDays, Account__PurgeIntervalMinutes
/// form.
/// </summary>
public sealed class AccountOptions
{
    public const string SectionName = "Account";

    /// <summary>
    /// How long after DELETE /account the records and blob prefix are retained
    /// before the purge job deletes them. Must not be shorter than the 30-day
    /// undo window (hard rule 8): a tombstoned account stays fully recoverable
    /// for the whole window, so this default equals it exactly (the same reason
    /// BlobOptions.OrphanGraceDays is 30).
    /// </summary>
    public int DeletionGraceDays { get; set; } = 30;

    /// <summary>How often the background purge job runs a pass. Hourly by default.</summary>
    public int PurgeIntervalMinutes { get; set; } = 60;

    public TimeSpan DeletionGracePeriod => TimeSpan.FromDays(DeletionGraceDays);

    public TimeSpan PurgeInterval => TimeSpan.FromMinutes(PurgeIntervalMinutes);
}
