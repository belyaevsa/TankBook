namespace Tankbook.Api.Notifications;

/// <summary>
/// APNs credentials for the silent sync nudge (docs/NOTIFICATIONS.md,
/// docs/SECURITY.md "Backend - secret management"). Bound from the "Apns"
/// section; environment form Apns__TeamId, Apns__KeyId, Apns__PrivateKey,
/// Apns__Topic. Everything here is a server-side secret: it never reaches a
/// client or a log (hard rule 11/12). Empty placeholders in appsettings.json;
/// real values come from the platform secret store at runtime.
/// </summary>
public sealed class ApnsOptions
{
    public const string SectionName = "Apns";

    /// <summary>The APNs host. api.push.apple.com for production; api.sandbox.push.apple.com for dev builds.</summary>
    public string Endpoint { get; set; } = "https://api.push.apple.com";

    /// <summary>The Apple Developer team id (10-char alphanumeric), the JWT "iss".</summary>
    public string? TeamId { get; set; }

    /// <summary>The APNs auth key id (10-char alphanumeric), the JWT "kid".</summary>
    public string? KeyId { get; set; }

    /// <summary>The ES256 (P-256) private key from the .p8 file, base64-encoded PKCS#8 (or PEM).</summary>
    public string? PrivateKey { get; set; }

    /// <summary>The app bundle id the push is addressed to (the apns-topic header).</summary>
    public string? Topic { get; set; }

    /// <summary>True when every credential needed to mint a provider token is present.</summary>
    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(TeamId) &&
        !string.IsNullOrWhiteSpace(KeyId) &&
        !string.IsNullOrWhiteSpace(PrivateKey) &&
        !string.IsNullOrWhiteSpace(Topic);
}
