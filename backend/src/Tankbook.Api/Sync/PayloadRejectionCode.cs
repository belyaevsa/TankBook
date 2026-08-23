namespace Tankbook.Api.Sync;

/// <summary>
/// Per-item payload rejection codes from docs/API.md (POST /sync/push) and
/// docs/SYNC.md ("Payload contract and versioning"). <see cref="None"/> means
/// the change was accepted. P4 maps these onto the wire result
/// (status: "rejected", error: &lt;code&gt;, pointer: &lt;json-pointer&gt;).
/// </summary>
public enum PayloadRejectionCode
{
    /// <summary>Accepted - the payload passed structural validation.</summary>
    None = 0,

    /// <summary>
    /// Envelope failure: payload not a JSON object, larger than 256 KB, or an
    /// empty / over-long entity_type. Wire: 422 <c>payload_invalid</c>.
    /// </summary>
    PayloadInvalid,

    /// <summary>
    /// The client's schema_version is newer than the server knows for this
    /// entity - the SERVER needs updating. Wire: 409 <c>schema_version_unsupported</c>.
    /// </summary>
    SchemaVersionUnsupported,

    /// <summary>
    /// The payload does not validate against the registered JSON Schema for
    /// (entity_type, schema_version); <see cref="PayloadValidationResult.Pointer"/>
    /// names the offending field. Wire: 422 <c>payload_schema_violation</c>.
    /// </summary>
    PayloadSchemaViolation,

    /// <summary>
    /// The client's schema_version is older than the server's minSupported.
    /// Push is refused but pull still works (never lock a user out of their own
    /// data). Wire: 426 <c>upgrade_required</c>.
    /// </summary>
    UpgradeRequired,
}

public static class PayloadRejectionCodeExtensions
{
    /// <summary>The wire code strings defined in docs/API.md.</summary>
    public static string ToWireCode(this PayloadRejectionCode code) => code switch
    {
        PayloadRejectionCode.None => "accepted",
        PayloadRejectionCode.PayloadInvalid => "payload_invalid",
        PayloadRejectionCode.SchemaVersionUnsupported => "schema_version_unsupported",
        PayloadRejectionCode.PayloadSchemaViolation => "payload_schema_violation",
        PayloadRejectionCode.UpgradeRequired => "upgrade_required",
        _ => throw new ArgumentOutOfRangeException(nameof(code), code, "Unknown payload rejection code."),
    };
}
