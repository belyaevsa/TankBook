namespace Tankbook.Api.Blobs;

/// <summary>
/// Blob pipeline configuration (docs/API.md "Attachments", docs/SYNC.md
/// "Attachments: the blob pipeline"). Bound from the "Blob" configuration
/// section; environment variables use the Blob__QuotaBytes, Blob__ImageMaxBytes,
/// Blob__UploadPresignMinutes, ... form. The two presign lifetimes are
/// deliberately distinct (docs/SYNC.md specifies ~15 min upload, ~10 min
/// download); they are not collapsed into one constant.
/// </summary>
public sealed class BlobOptions
{
    public const string SectionName = "Blob";

    /// <summary>Per-account storage quota in bytes. Generous free tier; metered like LLM usage.</summary>
    public long QuotaBytes { get; set; } = 5L * 1024 * 1024 * 1024;

    /// <summary>Size cap for image renditions (JPEG/PNG/HEIC), docs/SYNC.md: 25 MB.</summary>
    public long ImageMaxBytes { get; set; } = 25L * 1024 * 1024;

    /// <summary>Size cap for PDFs, docs/SYNC.md: 10 MB.</summary>
    public long PdfMaxBytes { get; set; } = 10L * 1024 * 1024;

    /// <summary>Presigned upload (PUT) lifetime, docs/SYNC.md: ~15 min.</summary>
    public int UploadPresignMinutes { get; set; } = 15;

    /// <summary>Presigned download (GET) lifetime, docs/SYNC.md: ~10 min.</summary>
    public int DownloadPresignMinutes { get; set; } = 10;

    /// <summary>
    /// Orphan grace period. A blob that is unreferenced by any live record, and
    /// whose referencing record was tombstoned longer ago than this, becomes
    /// sweepable. Defaults to the 30-day undo window (hard rule 8) so a blob
    /// whose record can still be restored is never swept out from under it.
    /// </summary>
    public int OrphanGraceDays { get; set; } = 30;

    /// <summary>How often the background orphan sweep runs a pass. Hourly by default.</summary>
    public int SweepIntervalMinutes { get; set; } = 60;

    public TimeSpan UploadPresignLifetime => TimeSpan.FromMinutes(UploadPresignMinutes);

    public TimeSpan DownloadPresignLifetime => TimeSpan.FromMinutes(DownloadPresignMinutes);

    public TimeSpan OrphanGracePeriod => TimeSpan.FromDays(OrphanGraceDays);

    public TimeSpan SweepInterval => TimeSpan.FromMinutes(SweepIntervalMinutes);
}
