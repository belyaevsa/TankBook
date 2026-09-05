using System.Security.Cryptography;
using System.Text.Json;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Config;

/// <summary>
/// GET /v1/config and GET /v1/config/public-key (docs/API.md reference data,
/// docs/CONFIG.md "Delivery"). Both are PUBLIC - no auth, no account - because
/// guests and signed-out users need config too. GET /config is a thin wire: it
/// reads the pre-selected signed document and answers 304 when the client's
/// ETag is current, keeping polling nearly free (throttled client-side to once
/// per 6 hours, docs/CONFIG.md).
/// </summary>
public static class ConfigEndpoints
{
    public const string CacheControl = "max-age=300, must-revalidate";

    public static async Task<IResult> GetConfig(
        IConfigReadService read,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        var result = await read.GetForServingAsync(cancellationToken);
        if (result is null)
        {
            return ProblemResponses.Problem(
                StatusCodes.Status503ServiceUnavailable,
                TankbookErrorCodes.ConfigUnavailable,
                "No config document is available.",
                "The server has no published config document. Clients fall back to bundled defaults.");
        }

        var etag = ComputeEtag(result);
        httpContext.Response.Headers.CacheControl = CacheControl;

        if (IfNoneMatchMatches(httpContext.Request, etag))
        {
            httpContext.Response.Headers.ETag = etag;
            // 304: no body, per the HTTP contract (docs/API.md GET /config).
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        httpContext.Response.Headers.ETag = etag;
        return Results.Text(ResponseBody(result), "application/json");
    }

    public static IResult GetPublicKey(ConfigSigner signer)
    {
        if (!signer.IsConfigured)
        {
            return ProblemResponses.Problem(
                StatusCodes.Status503ServiceUnavailable,
                TankbookErrorCodes.ConfigUnavailable,
                "The config signing key is not configured.",
                "Config:SigningKey is unset; there is no public key to expose.");
        }

        return Results.Ok(new PublicKeyResponse(signer.KeyId, signer.PublicKeyBase64));
    }

    /// <summary>
    /// A strong ETag derived from the version and the signed content: any change
    /// to either produces a new tag, so 304 is only returned for byte-identical
    /// documents. Computed over the canonical document bytes plus the signature,
    /// which are stable per version.
    /// </summary>
    internal static string ComputeEtag(ConfigServeResult result)
    {
        var canonical = ConfigCanonicalizer.Canonicalize(result.DocumentJson);
        using var sha = SHA256.Create();
        sha.TransformBlock(canonical, 0, canonical.Length, null, 0);
        var signatureBytes = Convert.FromBase64String(result.Signature);
        sha.TransformFinalBlock(signatureBytes, 0, signatureBytes.Length);
        return $"\"{result.Version}:{Convert.ToHexString(sha.Hash!).ToLowerInvariant()}\"";
    }

    private static bool IfNoneMatchMatches(HttpRequest request, string etag)
    {
        var header = request.Headers.IfNoneMatch.ToString();
        if (string.IsNullOrWhiteSpace(header))
        {
            return false;
        }

        if (header == "*")
        {
            return true;
        }

        foreach (var candidate in header.Split(','))
        {
            // Strip a possible weak prefix: a client may send W/"..." in
            // If-None-Match, and for GET the comparison succeeds regardless.
            var normalized = candidate.Trim();
            if (normalized.StartsWith("W/", StringComparison.Ordinal))
            {
                normalized = normalized[2..].Trim();
            }

            if (normalized == etag)
            {
                return true;
            }
        }

        return false;
    }

    private static string ResponseBody(ConfigServeResult result)
    {
        // Build the wire shape { document, signature, version } (docs/API.md).
        // document is served verbatim (the raw JSONB text), so a client caches
        // exactly what was signed - never a re-serialized form. Keep the bytes
        // in a buffer rather than round-tripping through an object graph.
        return "{\"document\":" + result.DocumentJson +
               ",\"signature\":" + JsonSerializer.Serialize(result.Signature) +
               ",\"version\":" + result.Version.ToString(System.Globalization.CultureInfo.InvariantCulture) + "}";
    }

    private sealed record PublicKeyResponse(string KeyId, string PublicKey);
}
