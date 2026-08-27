using System.Security.Cryptography;
using System.Text;

namespace Tankbook.Api.Http;

/// <summary>
/// Strong-ETag helpers shared by the reference-data endpoints (docs/API.md
/// conventions). An ETag is the SHA-256 of the exact response bytes, so a 304 is
/// only ever returned for a byte-identical body; <c>If-None-Match</c> honours a
/// comma list and the weak prefix, per RFC 9110.
/// </summary>
public static class EtagHelpers
{
    public static string ComputeEtag(string body)
    {
        using var sha = SHA256.Create();
        return $"\"{Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(body))).ToLowerInvariant()}\"";
    }

    public static bool IfNoneMatchMatches(HttpRequest request, string etag)
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
}
