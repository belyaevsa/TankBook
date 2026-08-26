using System.Security.Cryptography;
using System.Text;

namespace Tankbook.Api.Auth;

/// <summary>
/// Refresh tokens are opaque random strings. Only their SHA-256 hash is stored
/// (docs/API.md Auth, docs/SECURITY.md) - a database dump must not yield working
/// credentials. The token value exists on the wire and in the client's Keychain,
/// never on the server.
/// </summary>
public static class RefreshTokenHasher
{
    /// <summary>SHA-256 hex of the token value - what the refresh_tokens table stores.</summary>
    public static string Hash(string token)
        => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();

    /// <summary>Generates a fresh cryptographically random token of the given byte length.</summary>
    public static string Generate(int byteLength)
        => JwtCodec.Base64UrlEncode(RandomNumberGenerator.GetBytes(byteLength));
}
