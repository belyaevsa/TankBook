namespace Tankbook.Api.Auth;

/// <summary>
/// Authentication configuration, bound from the "Auth" section. The JWT signing
/// key is a secret: it lives in the platform secret store, never in
/// appsettings.json (docs/SECURITY.md "Backend - secret management"). When it is
/// unset the issuer generates an ephemeral key for the process lifetime (dev
/// only, logged as a warning) - tokens then do not survive a restart, which is
/// why production must set it. Environment form: Auth__JwtSigningKeyBase64.
/// </summary>
public sealed class AuthOptions
{
    public const string SectionName = "Auth";

    /// <summary>Base64-encoded PKCS#8 RSA private key for access-token signing.</summary>
    public string? JwtSigningKeyBase64 { get; set; }

    /// <summary>JWT issuer claim for the access tokens this server mints.</summary>
    public string Issuer { get; set; } = "tankbook";

    /// <summary>JWT audience claim for the access tokens this server mints.</summary>
    public string Audience { get; set; } = "tankbook-app";

    /// <summary>Access-token lifetime (docs/API.md: JWT, ~1 hour).</summary>
    public int AccessTokenLifetimeMinutes { get; set; } = 60;

    /// <summary>Refresh-token lifetime before expiry forces a re-sign-in.</summary>
    public int RefreshTokenLifetimeDays { get; set; } = 90;

    /// <summary>Entropy in bytes of a freshly minted refresh token.</summary>
    public int RefreshTokenBytes { get; set; } = 32;

    /// <summary>Apple's public key set (never a secret; signatures are still verified).</summary>
    public string AppleJwksUrl { get; set; } = "https://appleid.apple.com/auth/keys";

    /// <summary>Google's public key set (never a secret; signatures are still verified).</summary>
    public string GoogleJwksUrl { get; set; } = "https://www.googleapis.com/oauth2/v3/certs";

    /// <summary>How long a fetched JWKS document is cached before re-fetch.</summary>
    public int JwksCacheMinutes { get; set; } = 360;

    /// <summary>Allowed clock skew when checking exp/iat/nbf.</summary>
    public int ClockSkewSeconds { get; set; } = 30;

    /// <summary>Reject identity tokens whose email_verified is not true.</summary>
    public bool RequireEmailVerified { get; set; } = true;
}
