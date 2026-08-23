namespace Tankbook.Api.Config;

/// <summary>
/// Remote config signing configuration, bound from the "Config" section
/// (Config:SigningKey). The signing key is a secret: it lives in the platform
/// secret store, never in appsettings.json (which holds an empty placeholder);
/// only a dev-only default sits in appsettings.Development.json (docs/SECURITY.md
/// "Backend - secret management"). Environment form: Config__SigningKey.
/// </summary>
public sealed class ConfigSigningOptions
{
    public const string SectionName = "Config";

    /// <summary>Base64-encoded 32-byte Ed25519 private seed.</summary>
    public string? SigningKey { get; set; }
}
