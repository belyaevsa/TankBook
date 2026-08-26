using System.Security.Cryptography;
using System.Text.Json;

namespace Tankbook.Api.Auth;

/// <summary>
/// A JSON Web Key Set (RFC 7517) as served by Apple and Google. The keys are
/// public, so they are fetched (with caching) rather than shipped - but a
/// token's signature is still verified against them, never trusted
/// (docs/SECURITY.md).
/// </summary>
public sealed class JwksDocument
{
    public IReadOnlyList<JsonWebKey> Keys { get; init; } = Array.Empty<JsonWebKey>();

    public static JwksDocument Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var keys = document.RootElement
            .GetProperty("keys")
            .EnumerateArray()
            .Select(JsonWebKey.FromJson)
            .ToList();
        return new JwksDocument { Keys = keys };
    }
}

/// <summary>One RSA public key from a JWKS document, by its kid.</summary>
public sealed record JsonWebKey(string Kid, string Kty, string Alg, string Modulus, string Exponent)
{
    public static JsonWebKey FromJson(JsonElement element)
    {
        static string Text(JsonElement e, string name) =>
            e.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString() ?? ""
                : "";

        return new JsonWebKey(
            Text(element, "kid"),
            Text(element, "kty"),
            Text(element, "alg"),
            Text(element, "n"),
            Text(element, "e"));
    }

    /// <summary>Materializes an RSA public key from the JWK's n/e parameters.</summary>
    public RSA ToRsa()
    {
        var rsa = RSA.Create();
        rsa.ImportParameters(new RSAParameters
        {
            Modulus = JwtCodec.Base64UrlDecode(Modulus),
            Exponent = JwtCodec.Base64UrlDecode(Exponent),
        });
        return rsa;
    }
}
