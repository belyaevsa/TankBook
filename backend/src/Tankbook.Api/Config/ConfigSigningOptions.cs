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

    /// <summary>
    /// The committed dev-only placeholder Ed25519 seed (the same value in
    /// appsettings.json and appsettings.Development.json). A production server
    /// must refuse to start with this (or with none): anyone who reads this repo
    /// can reproduce the keypair and forge config documents (PR.34).
    /// </summary>
    public const string DevPlaceholderSeed = "IpsG7l75fgQtx1iYnwLA7ekrhHbkB8dy3sMjbo4OUKM=";

    /// <summary>Base64-encoded 32-byte Ed25519 private seed.</summary>
    public string? SigningKey { get; set; }
}
