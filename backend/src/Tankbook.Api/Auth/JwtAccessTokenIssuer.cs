using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Tankbook.Api.Auth;

/// <summary>
/// Mints and validates the server's own access tokens (docs/API.md: JWT, ~1
/// hour). RS256, keyed with a kid so the key can rotate without invalidating
/// live sessions (docs/SECURITY.md). The bearer middleware and the P4.2/P4.3
/// endpoints validate through <see cref="TryValidate"/>.
/// </summary>
public sealed class JwtAccessTokenIssuer
{
    private readonly RSA _rsa;
    private readonly AuthOptions _options;
    private readonly TimeProvider _time;

    public JwtAccessTokenIssuer(IOptions<AuthOptions> options, TimeProvider time)
    {
        _options = options.Value;
        _time = time;

        var key = _options.JwtSigningKeyBase64;
        if (string.IsNullOrWhiteSpace(key))
        {
            // Dev-only fallback: an ephemeral key lasts one process. Production
            // must set Auth:JwtSigningKeyBase64 from the secret store.
            _rsa = RSA.Create(2048);
            IsEphemeral = true;
        }
        else
        {
            _rsa = RSA.Create();
            _rsa.ImportPkcs8PrivateKey(Convert.FromBase64String(key), out _);
            IsEphemeral = false;
        }
    }

    public JwtAccessTokenIssuer(IOptions<AuthOptions> options)
        : this(options, TimeProvider.System)
    {
    }

    /// <summary>True when the signing key was generated for this process, not configured.</summary>
    public bool IsEphemeral { get; }

    /// <summary>A short fingerprint of the public key, carried as the token's kid.</summary>
    public string KeyId => Convert.ToHexString(SHA256.HashData(_rsa.ExportRSAPublicKey()))[..16].ToLowerInvariant();

    /// <summary>Mints an access token carrying the account and device identity.</summary>
    public string Issue(Guid accountId, Guid deviceId)
    {
        var now = _time.GetUtcNow();
        var header = JsonSerializer.Serialize(new { alg = "RS256", typ = "JWT", kid = KeyId });
        var payload = JsonSerializer.Serialize(new
        {
            iss = _options.Issuer,
            aud = _options.Audience,
            sub = accountId.ToString(),
            device_id = deviceId.ToString(),
            iat = now.ToUnixTimeSeconds(),
            exp = now.AddMinutes(_options.AccessTokenLifetimeMinutes).ToUnixTimeSeconds(),
        });
        return JwtCodec.Sign(header, payload, _rsa);
    }

    /// <summary>Validates signature, expiry, and extracts the account + device identity.</summary>
    public bool TryValidate(string token, out Guid accountId, out Guid deviceId)
    {
        accountId = Guid.Empty;
        deviceId = Guid.Empty;

        if (!JwtCodec.TryDecode(token, out _, out var payloadJson) ||
            !JwtCodec.VerifyRsa256(token, _rsa))
        {
            return false;
        }

        JsonDocument payload;
        try
        {
            payload = JsonDocument.Parse(payloadJson);
        }
        catch (JsonException)
        {
            return false;
        }

        using (payload)
        {
            var root = payload.RootElement;
            if (!root.TryGetProperty("sub", out var sub) ||
                !Guid.TryParse(sub.GetString(), out accountId) ||
                !root.TryGetProperty("device_id", out var device) ||
                !Guid.TryParse(device.GetString(), out deviceId))
            {
                return false;
            }

            if (!root.TryGetProperty("exp", out var exp) ||
                !exp.TryGetInt64(out var expSeconds) ||
                expSeconds <= _time.GetUtcNow().ToUnixTimeSeconds())
            {
                return false;
            }

            return true;
        }
    }
}
