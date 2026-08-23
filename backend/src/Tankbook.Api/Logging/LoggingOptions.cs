namespace Tankbook.Api.Logging;

/// <summary>
/// Bound from the "Tankbook:Logging" configuration section. Carries the pieces
/// of the logging pipeline that are configuration rather than code: the
/// account-hash salt, the sensitive-value policy, and the console format.
/// The salt is never committed with a production value; the code default is a
/// dev placeholder and production sets Tankbook__Logging__HashSalt from secrets.
/// </summary>
public sealed class LoggingOptions
{
    public const string SectionName = "Tankbook:Logging";

    /// <summary>Pepper for the salted accountHash (docs/LOGGING.md §1). Dev-only default.</summary>
    public string HashSalt { get; set; } = "tankbook-dev-hash-salt-change-me";

    /// <summary>
    /// When true (the default) Sensitive values are masked before they can be
    /// written. Debugging a problem usually needs real values, so a Development
    /// build may opt out explicitly; production must keep this true.
    /// </summary>
    public bool RedactSensitiveValues { get; set; } = true;

    /// <summary>
    /// "json" writes one JSON object per line; "text" writes human-readable
    /// lines. Empty means "choose from the environment": text in Development,
    /// json everywhere else.
    /// </summary>
    public string Format { get; set; } = "";
}
