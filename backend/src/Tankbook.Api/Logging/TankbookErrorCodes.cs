namespace Tankbook.Api.Logging;

/// <summary>
/// The stable error codes that can appear on an ERROR log line
/// (docs/LOGGING.md §3 Errors, sourced from docs/API.md). The server validates
/// payload structure, never domain meaning, so codes stay few.
/// </summary>
public static class TankbookErrorCodes
{
    /// <summary>Push batch rejected whole: client schemaVersion &lt; server minSupported (426).</summary>
    public const string UpgradeRequired = "upgrade_required";

    /// <summary>Per-item: payload is not an object, too large, or bad entityType (422).</summary>
    public const string PayloadInvalid = "payload_invalid";

    /// <summary>Per-item: schema_version newer than the server knows (409).</summary>
    public const string SchemaVersionUnsupported = "schema_version_unsupported";

    /// <summary>Per-item: payload fails its registered JSON Schema; pointer names the field (422).</summary>
    public const string PayloadSchemaViolation = "payload_schema_violation";

    /// <summary>Unhandled exception: no domain meaning, reproduced from the error context fields.</summary>
    public const string InternalError = "internal_error";
}
