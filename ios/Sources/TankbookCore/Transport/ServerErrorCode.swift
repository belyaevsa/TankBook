import Foundation

/// The stable `code` member of the server's problem+json error envelope
/// (docs/API.md -> "Error envelope"). Grouped by what the CLIENT must do
/// differently - a code names the next step, never the call site. Raw values
/// match `TankbookErrorCodes` on the server byte-for-byte. A code is a Safe,
/// loggable value (hard rule 12).
public enum ServerErrorCode: String, Sendable, Equatable, CaseIterable {
    // ---- Envelope-level (any endpoint) ----
    case internalError = "internal_error"
    case payloadInvalid = "payload_invalid"
    case payloadTooLarge = "payload_too_large"
    case rateLimited = "rate_limited"
    case upstreamUnavailable = "upstream_unavailable"
    case notFound = "not_found"
    case tierRefused = "tier_refused"
    case upgradeRequired = "upgrade_required"

    // ---- Auth ----
    case tokenInvalid = "token_invalid"
    case refreshReused = "refresh_reused"
    case clockSkew = "clock_skew"
    case providerUnsupported = "provider_unsupported"

    // ---- Devices / account ----
    case deviceRevoked = "device_revoked"
    case accountDeviceNotFound = "account_device_not_found"

    // ---- Blobs ----
    case blobNotFound = "blob_not_found"
    case blobConflict = "blob_conflict"
    case blobQuotaExceeded = "blob_quota_exceeded"

    // ---- Import ----
    case importFormatUnsupported = "import_format_unsupported"
    case importMismatch = "import_mismatch"
    case importNotFound = "import_not_found"

    // ---- Config ----
    case configUnavailable = "config_unavailable"

    /// Parses a raw `code` member. nil for an unknown or malformed value - an
    /// older client must survive a code a newer server added, degrading to the
    /// status-based classification (PR.9); the raw string is still logged.
    public init?(raw: String?) {
        guard let raw else { return nil }
        self.init(rawValue: raw)
    }
}
