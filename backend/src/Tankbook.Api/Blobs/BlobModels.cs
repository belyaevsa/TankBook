using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Tankbook.Api.Blobs;

/// <summary>POST /blobs/begin request body (docs/API.md).</summary>
public sealed record BlobBeginRequest(string? Sha256, long? Size, string? ContentType);

/// <summary>POST /blobs/commit request body (docs/API.md).</summary>
public sealed record BlobCommitRequest(string? Sha256);

/// <summary>
/// POST /blobs/begin response: <c>{ status: "exists" }</c> on dedupe, or
/// <c>{ status: "upload", url, expiresAt }</c> with a presigned PUT. The URL and
/// expiry are omitted when the blob already exists.
/// </summary>
public sealed class BlobBeginResponse
{
    public string Status { get; init; } = string.Empty;

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Url { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTimeOffset? ExpiresAt { get; init; }

    public static BlobBeginResponse Exists => new() { Status = "exists" };

    public static BlobBeginResponse Upload(string url, DateTimeOffset expiresAt)
        => new() { Status = "upload", Url = url, ExpiresAt = expiresAt };
}

/// <summary>The broad class a declared content type falls into; each class has its own size cap.</summary>
public enum BlobKind
{
    Image,
    Pdf,
}

/// <summary>
/// The contentType allow-list (docs/SYNC.md hygiene: JPEG/PNG/HEIC/PDF). The
/// declared type must be one of these; anything else is refused before a
/// presigned URL is minted. Media-type parameters are stripped (e.g.
/// "image/jpeg; charset=..." is still image/jpeg) and matching is
/// case-insensitive.
/// </summary>
public static class BlobContentTypes
{
    private static readonly Regex Sha256Pattern = new("^[0-9a-f]{64}$", RegexOptions.Compiled);

    /// <summary>
    /// True when <paramref name="sha256"/> is a 64-char lowercase hex digest. This
    /// is a security check, not just a shape check: the digest is part of the
    /// storage key ({account_id}/{sha256}), so a non-conforming value could carry
    /// path separators or ".." and escape the account prefix.
    /// </summary>
    public static bool IsValidSha256(string? sha256) =>
        sha256 is not null && Sha256Pattern.IsMatch(sha256);

    public static bool TryClassify(string? contentType, out BlobKind kind, out string normalized)
    {
        kind = default;
        normalized = Normalize(contentType);
        switch (normalized)
        {
            case "image/jpeg":
            case "image/png":
            case "image/heic":
            case "image/heif":
                kind = BlobKind.Image;
                return true;
            case "application/pdf":
                kind = BlobKind.Pdf;
                return true;
            default:
                return false;
        }
    }

    public static long SizeCap(BlobOptions options, BlobKind kind) =>
        kind == BlobKind.Pdf ? options.PdfMaxBytes : options.ImageMaxBytes;

    private static string Normalize(string? contentType)
    {
        if (string.IsNullOrWhiteSpace(contentType))
        {
            return string.Empty;
        }

        var value = contentType.Trim().ToLowerInvariant();
        var separator = value.IndexOf(';');
        return separator >= 0 ? value[..separator].Trim() : value;
    }
}
