namespace Tankbook.Api.Options;

/// <summary>
/// S3-compatible blob storage configuration (docs/SYNC.md: provider-agnostic,
/// MinIO for local dev). Bound from the "S3" configuration section;
/// environment variables use the S3__Endpoint, S3__Bucket, S3__AccessKey,
/// S3__SecretKey, S3__UseSsl form.
/// </summary>
public sealed class S3Options
{
    public const string SectionName = "S3";

    public string? Endpoint { get; set; }

    public string? Bucket { get; set; }

    public string? AccessKey { get; set; }

    public string? SecretKey { get; set; }

    public bool UseSsl { get; set; }
}
