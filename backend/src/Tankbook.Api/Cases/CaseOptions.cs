namespace Tankbook.Api.Cases;

/// <summary>
/// Debug case configuration (docs/API.md "Debug cases", docs/SECURITY.md "Debug
/// cases"). Bound from the "Cases" section; environment variables use the
/// Cases__RetentionDays form. The size bounds are compiled: the body cap is
/// derived from them (<see cref="Http.BodySizeLimits.CaseBytes"/>), and a number
/// in two places is a bug (docs/PRACTICES.md).
/// </summary>
public sealed class CaseOptions
{
    public const string SectionName = "Cases";

    /// <summary>The most parts one case may carry: a manifest, a log and a few scans of three parts each.</summary>
    public const int MaxParts = 40;

    /// <summary>The largest single part: a full-resolution phone photo with headroom.</summary>
    public const long MaxPartBytes = 12L * 1024 * 1024;

    /// <summary>The largest case in total.</summary>
    public const long MaxTotalBytes = 48L * 1024 * 1024;

    /// <summary>How long a case is kept (hard rule 9: 30 days, matching the tombstone/undo window).</summary>
    public int RetentionDays { get; set; } = 30;

    /// <summary>How often the background purge job runs a pass.</summary>
    public int PurgeIntervalMinutes { get; set; } = 60;

    /// <summary>
    /// Where accepted parts wait for the uploader. In production a host folder
    /// mounted into every container colour (backend/scripts/deploy-blue-green.sh),
    /// so a case accepted just before a deploy is still uploaded after it.
    /// </summary>
    public string SpoolPath { get; set; } = Path.Combine(Path.GetTempPath(), "tankbook-case-spool");

    /// <summary>How often the uploader looks for pending cases when nothing woke it.</summary>
    public int UploadIntervalSeconds { get; set; } = 30;

    /// <summary>How many times one case's upload is tried before it is recorded as failed.</summary>
    public int MaxUploadAttempts { get; set; } = 10;

    /// <summary>How long a claim on a case holds before another container may take it over.</summary>
    public int UploadClaimMinutes { get; set; } = 5;

    public TimeSpan RetentionPeriod => TimeSpan.FromDays(RetentionDays);

    public TimeSpan PurgeInterval => TimeSpan.FromMinutes(PurgeIntervalMinutes);

    public TimeSpan UploadInterval => TimeSpan.FromSeconds(UploadIntervalSeconds);

    public TimeSpan UploadClaim => TimeSpan.FromMinutes(UploadClaimMinutes);
}
