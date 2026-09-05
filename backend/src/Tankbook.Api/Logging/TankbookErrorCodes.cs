namespace Tankbook.Api.Logging;

/// <summary>
/// The stable error codes that can appear on an ERROR log line and, since PR.9,
/// on the wire as the `code` member of every problem+json error body
/// (docs/API.md -> "Error envelope", docs/ERRORS.md). Grouped by what the CLIENT
/// must do differently - a code names the next step, never the call site. The
/// server validates payload structure, never domain meaning (hard rule 9), so
/// codes stay few.
/// </summary>
public static class TankbookErrorCodes
{
    // ---- Payload contract (sync per-item `rejected` codes + the push 426) ----

    /// <summary>Push batch rejected whole: client schemaVersion &lt; server minSupported (426).</summary>
    public const string UpgradeRequired = "upgrade_required";

    /// <summary>
    /// Request shape is wrong: a required field is missing, malformed or out of
    /// range, an entityType is bad, or the request cannot be processed as offered.
    /// Also the per-item push code (422).
    /// </summary>
    public const string PayloadInvalid = "payload_invalid";

    /// <summary>Per-item: schema_version newer than the server knows (409).</summary>
    public const string SchemaVersionUnsupported = "schema_version_unsupported";

    /// <summary>Per-item: payload fails its registered JSON Schema; pointer names the field (422).</summary>
    public const string PayloadSchemaViolation = "payload_schema_violation";

    // ---- Envelope-level failures (any endpoint) ----

    /// <summary>Unhandled exception: no domain meaning, reproduced from the error context fields (500).</summary>
    public const string InternalError = "internal_error";

    /// <summary>A request body or attachment exceeds the endpoint's size cap (413).</summary>
    public const string PayloadTooLarge = "payload_too_large";

    /// <summary>Rate- or period-limited; the Retry-After header names the wait (429).</summary>
    public const string RateLimited = "rate_limited";

    /// <summary>An upstream service the endpoint depends on failed (502, LLM provider).</summary>
    public const string UpstreamUnavailable = "upstream_unavailable";

    /// <summary>The request names a route the server does not serve (unmatched 404).</summary>
    public const string NotFound = "not_found";

    /// <summary>A bearer/identity/refresh token was rejected - an auth event, never a gate (401).</summary>
    public const string TokenInvalid = "token_invalid";

    /// <summary>A rotated refresh token was replayed; the whole chain is revoked - theft signal (401).</summary>
    public const string RefreshReused = "refresh_reused";

    /// <summary>The identity token was rejected because the device clock is off (401).</summary>
    public const string ClockSkew = "clock_skew";

    /// <summary>The sign-in provider is not one this server offers (400).</summary>
    public const string ProviderUnsupported = "provider_unsupported";

    /// <summary>The account is gone or this device was revoked - re-onboard (410).</summary>
    public const string DeviceRevoked = "device_revoked";

    /// <summary>A device id does not belong to this account (404 on the account endpoints).</summary>
    public const string AccountDeviceNotFound = "account_device_not_found";

    /// <summary>A server-side capability/tier this client does not have (402).</summary>
    public const string TierRefused = "tier_refused";

    // ---- Blobs ----

    /// <summary>No attachment with this sha256 exists for this account (404).</summary>
    public const string BlobNotFound = "blob_not_found";

    /// <summary>The begin/upload/commit protocol was violated; re-begin (409).</summary>
    public const string BlobConflict = "blob_conflict";

    /// <summary>The account's attachment storage quota is exhausted (429).</summary>
    public const string BlobQuotaExceeded = "blob_quota_exceeded";

    // ---- Import ----

    /// <summary>The declared source format is not offered (415).</summary>
    public const string ImportFormatUnsupported = "import_format_unsupported";

    /// <summary>The file does not look like the format the user declared (422).</summary>
    public const string ImportMismatch = "import_mismatch";

    /// <summary>No stored parse has this id (404).</summary>
    public const string ImportNotFound = "import_not_found";

    // ---- Config ----

    /// <summary>The server has no published config document / signing key (503).</summary>
    public const string ConfigUnavailable = "config_unavailable";
}
