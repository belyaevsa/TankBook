namespace Tankbook.Api.Import;

/// <summary>
/// Import parsing configuration (docs/API.md "Import parsing", docs/SECURITY.md
/// "Import files at rest"). Bound from the "Import" configuration section;
/// environment variables use the Import__MaxFileBytes, Import__RetentionDays,
/// Import__PurgeIntervalMinutes form.
/// </summary>
public sealed class ImportOptions
{
    public const string SectionName = "Import";

    /// <summary>Size cap for an uploaded third-party export (docs/API.md: file &lt;= 8 MB).</summary>
    public long MaxFileBytes { get; set; } = 8L * 1024 * 1024;

    /// <summary>How long a stored file and its parse result are kept (docs/SECURITY.md: 30 days, matching the tombstone/undo window).</summary>
    public int RetentionDays { get; set; } = 30;

    /// <summary>How often the background purge job runs a pass.</summary>
    public int PurgeIntervalMinutes { get; set; } = 60;

    public TimeSpan RetentionPeriod => TimeSpan.FromDays(RetentionDays);

    public TimeSpan PurgeInterval => TimeSpan.FromMinutes(PurgeIntervalMinutes);
}
