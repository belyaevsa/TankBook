using System.Security.Cryptography;
using System.Text;

namespace Tankbook.Api.Auth;

/// <summary>
/// Compact JWT helpers shared by the idToken verifier, the access-token issuer,
/// and the test signer. RS256 only (both Apple and Google sign RS256, and the
/// server mints RS256 access tokens) - no algorithm confusion: the algorithm is
/// fixed, never read off the token.
/// </summary>
public static class JwtCodec
{
    public static string Base64UrlEncode(byte[] bytes)
        => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = (padded.Length % 4) switch
        {
            2 => padded + "==",
            3 => padded + "=",
            _ => padded,
        };
        return Convert.FromBase64String(padded);
    }

    /// <summary>Builds a signed JWT from the raw header and payload JSON.</summary>
    public static string Sign(string headerJson, string payloadJson, RSA rsa)
    {
        var header = Base64UrlEncode(Encoding.UTF8.GetBytes(headerJson));
        var payload = Base64UrlEncode(Encoding.UTF8.GetBytes(payloadJson));
        var signingInput = Encoding.ASCII.GetBytes(header + "." + payload);
        var signature = rsa.SignData(signingInput, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        return header + "." + payload + "." + Base64UrlEncode(signature);
    }

    /// <summary>Decodes the header and payload JSON of a JWT without verifying.</summary>
    public static bool TryDecode(string token, out string headerJson, out string payloadJson)
    {
        headerJson = "";
        payloadJson = "";
        if (string.IsNullOrWhiteSpace(token))
        {
            return false;
        }

        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        try
        {
            headerJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[0]));
            payloadJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[1]));
            return true;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    /// <summary>Verifies the RS256 signature over the JWT's header.payload.</summary>
    public static bool VerifyRsa256(string token, RSA rsa)
    {
        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        byte[] signature;
        try
        {
            signature = Base64UrlDecode(parts[2]);
        }
        catch (FormatException)
        {
            return false;
        }

        var signingInput = Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]);
        try
        {
            return rsa.VerifyData(signingInput, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }
        catch (CryptographicException)
        {
            return false;
        }
    }
}
