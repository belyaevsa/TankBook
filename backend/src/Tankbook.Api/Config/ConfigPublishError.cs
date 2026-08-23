namespace Tankbook.Api.Config;

/// <summary>
/// A typed refusal from <see cref="ConfigPublishService.PublishAsync"/>. Not an
/// exception: the publish path is a routine internal operation and its failures
/// are ordinary control flow that callers must be able to match on.
/// </summary>
public enum ConfigPublishErrorKind
{
    /// <summary>The operation succeeded; no error.</summary>
    None = 0,

    /// <summary>The document is not a valid config document (schema violation).</summary>
    SchemaValidationFailed,

    /// <summary>The document's version is not higher than the current highest (rollback protection, docs/CONFIG.md).</summary>
    VersionNotMonotonic,

    /// <summary>The document is not parseable JSON.</summary>
    InvalidDocument,

    /// <summary>No signing key is configured, so no signature can be produced.</summary>
    SigningKeyNotConfigured,
}

/// <summary>The reason a publish was refused, with a human-readable detail.</summary>
public sealed record ConfigPublishError(ConfigPublishErrorKind Kind, string Detail)
{
    public static readonly ConfigPublishError None = new(ConfigPublishErrorKind.None, "");

    public bool IsSuccess => Kind == ConfigPublishErrorKind.None;
}

/// <summary>The outcome of a publish attempt.</summary>
public sealed record ConfigPublishResult(ConfigPublishError Error, int Version = 0)
{
    public bool IsSuccess => Error.IsSuccess;
}
