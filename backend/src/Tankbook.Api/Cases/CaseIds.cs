using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace Tankbook.Api.Cases;

/// <summary>
/// Case ids are meant to be read aloud and pasted: ten Crockford base32
/// characters in two groups of five (<c>K7Q2M-9XDRA</c>) - 50 random bits, no
/// I, L, O or U to misread. The id is the only way to the case, so it is drawn
/// from a cryptographic source, never derived from the sender.
/// </summary>
public static partial class CaseIds
{
    private const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    public static string New()
    {
        Span<byte> bytes = stackalloc byte[10];
        RandomNumberGenerator.Fill(bytes);
        Span<char> chars = stackalloc char[11];
        var at = 0;
        for (var i = 0; i < 10; i++)
        {
            if (i == 5)
            {
                chars[at++] = '-';
            }

            chars[at++] = Alphabet[bytes[i] & 31];
        }

        return new string(chars);
    }

    /// <summary>A pasted id, normalised: upper case, the dash where it belongs; null when it cannot be one.</summary>
    public static string? Normalize(string? text)
    {
        if (text is null)
        {
            return null;
        }

        var compact = text.Trim().Replace("-", string.Empty, StringComparison.Ordinal).ToUpperInvariant();
        if (!Compact().IsMatch(compact))
        {
            return null;
        }

        return $"{compact[..5]}-{compact[5..]}";
    }

    [GeneratedRegex("^[0-9A-HJKMNP-TV-Z]{10}$")]
    private static partial Regex Compact();
}
