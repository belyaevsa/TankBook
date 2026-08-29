using Tankbook.Api.Sync;

namespace Tankbook.Api.Http;

/// <summary>
/// Per-endpoint request-body caps (docs/API.md "Request body caps",
/// docs/PRACTICES.md S9, PR.17). The Kestrel default (30 MB) is below a maximal
/// legal sync push batch, so the server limit is raised to the push cap and each
/// endpoint is then capped explicitly. An oversize body is a 413 problem+json
/// carrying its traceId (hard rule 7), never a bare connection reset.
/// </summary>
public static class BodySizeLimits
{
    /// <summary>
    /// A maximal legal push batch (docs/API.md: &lt;= 200 changes, each payload
    /// &lt;= 256 KB) plus 1 KB of per-change envelope overhead and 1 MB of array
    /// envelope. References the same constants the validator and sync service
    /// enforce, so this cap can never drift below what a legitimate client may
    /// legally send (docs/PRACTICES.md: every number in two places is a bug).
    /// </summary>
    public const long PushBytes =
        SyncService.MaxChangesPerBatch * (PayloadValidator.MaxPayloadBytes + 1024) + 1024 * 1024;

    /// <summary>
    /// The base64 image body is capped at 4 MB by LlmGatewayOptions.MaxImageBytes;
    /// 6 MB gives the { kind, image, hints } envelope comfortable headroom.
    /// </summary>
    public const long ExtractBytes = 6L * 1024 * 1024;

    /// <summary>
    /// docs/API.md: import file &lt;= 8 MB, plus the multipart wrapper (boundary
    /// and the format field). A body cap of exactly 8 MB would reject a legal
    /// 8 MB file, so the cap is the file bound plus 1 MB of envelope.
    /// </summary>
    public const long ImportBytes = 8L * 1024 * 1024 + 1024 * 1024;

    /// <summary>
    /// The operator publishes a full catalog pack; a region's dictionary is far
    /// larger than any user request body. The "everything else is 64 KB" rule
    /// (docs/API.md) deliberately does not apply here.
    /// </summary>
    public const long CatalogPublishBytes = 8L * 1024 * 1024;

    /// <summary>Everything else (auth, blobs begin/commit, account push-token): tiny bodies.</summary>
    public const long DefaultBytes = 64L * 1024;

    /// <summary>
    /// Declares the endpoint's request-body cap. Carried as endpoint metadata and
    /// read by <see cref="BodySizeLimitMiddleware"/> after routing - the same
    /// mechanism the rate limiter uses, so it works regardless of how the
    /// endpoint was mapped (group, nested group, or top-level).
    /// </summary>
    public static IEndpointConventionBuilder WithBodySizeLimit(this IEndpointConventionBuilder builder, long maxBytes)
        => builder.WithMetadata(new BodySizeLimitAttribute(maxBytes));
}

/// <summary>The endpoint's request-body cap in bytes (read by <see cref="BodySizeLimitMiddleware"/>).</summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
public sealed class BodySizeLimitAttribute : Attribute
{
    public BodySizeLimitAttribute(long maxBytes) => MaxBytes = maxBytes;

    public long MaxBytes { get; }
}
