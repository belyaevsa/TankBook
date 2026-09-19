namespace Tankbook.Api.Reference;

/// <summary>
/// The cold-start country hint (docs/API.md "detectedCountry", RV.115): a coarse
/// country the edge derived from the connection IP, read from one request
/// header and handed back on an UNCACHEABLE response only. It is computed per
/// request and never stored, never logged beyond shape, and never read by any
/// endpoint - a default input the device outranks with the user's own history
/// (hard rule 13). No header, or a value that is not two letters, is no hint:
/// the client orders exactly as before.
/// </summary>
public static class DetectedCountry
{
    /// <summary>The header the edge sets. Cloudflare's name is the default; a
    /// deployment behind another proxy configures its own.</summary>
    public const string DefaultHeader = "CF-IPCountry";

    public static string? From(HttpRequest request, string? headerName)
    {
        var header = string.IsNullOrWhiteSpace(headerName) ? DefaultHeader : headerName;
        var value = request.Headers[header].ToString().Trim();
        if (value.Length != 2 || !char.IsAsciiLetter(value[0]) || !char.IsAsciiLetter(value[1]))
        {
            return null;
        }

        return value.ToUpperInvariant();
    }
}
