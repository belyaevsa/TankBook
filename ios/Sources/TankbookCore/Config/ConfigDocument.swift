import Foundation

/// A remote config document as served by `GET /v1/config`
/// (docs/CONFIG.md, `backend/src/Tankbook.Api/Config/config.schema.json`).
///
/// Typed fields, never a stringly-typed lookup: a renamed key is a compile error,
/// and the coverage test can assert that every documented remote key maps to a
/// field (docs/CONFIG.md -> "How code consumes it", rule 2).
///
/// The **raw bytes are kept alongside the typed view**. Two reasons, both load
/// bearing: the signature is over the canonical form of exactly these bytes, and
/// the cache stores the document verbatim so a future build immediately
/// understands keys this build does not know, with no refetch.
public struct ConfigDocument: Sendable, Equatable {
    /// The document exactly as served. Never re-encode this to store it.
    public let rawBytes: Data

    public let version: Int
    public let issuedAt: Date
    public let notAfter: Date
    public let apiBaseURL: URL?
    public let tier2OnDeviceLLM: Bool
    public let tier3CloudFallback: Bool
    public let llmQuota: LLMQuota
    public let ocrConfidenceThreshold: Double
    public let minSchemaVersion: Int
    public let referencePacks: ReferencePacks
    public let maintenance: MaintenanceNotice?
    public let rolloutSalt: String
    public let flags: [String: FeatureFlag]

    public struct LLMQuota: Sendable, Equatable, Decodable {
        public let onDeviceLLM: Int
        public let cloudFallback: Int

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            onDeviceLLM = try container.decodeFlexibleInt(forKey: .onDeviceLLM)
            cloudFallback = try container.decodeFlexibleInt(forKey: .cloudFallback)
        }

        enum CodingKeys: String, CodingKey {
            case onDeviceLLM
            case cloudFallback
        }
    }

    public struct ReferencePacks: Sendable, Equatable, Decodable {
        public let rates: Int
        public let catalog: Int

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rates = try container.decodeFlexibleInt(forKey: .rates)
            catalog = try container.decodeFlexibleInt(forKey: .catalog)
        }

        enum CodingKeys: String, CodingKey {
            case rates
            case catalog
        }
    }

    /// The one user-visible config surface, and deliberately inert: plain text
    /// only, no markup, no arbitrary URLs, and it may never prompt for
    /// credentials (docs/CONFIG.md -> "Defence in depth"). The server schema
    /// already rejects `<`, `>` and `&`; the client treats the field as plain
    /// text regardless, because a client must not depend on server validation
    /// for its own safety.
    public struct MaintenanceNotice: Sendable, Equatable {
        public let text: String
        public let severity: Severity
        public let until: Date

        public enum Severity: String, Sendable, Equatable {
            case info
            case warning
        }
    }

    public struct FeatureFlag: Sendable, Equatable, Decodable {
        public let enabled: Bool
        public let rolloutPercent: Int

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decode(Bool.self, forKey: .enabled)
            rolloutPercent = try container.decodeFlexibleInt(forKey: .rolloutPercent)
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case rolloutPercent
        }
    }

    /// Decodes a served document, retaining its exact bytes.
    ///
    /// Unknown keys are ignored for the typed view and preserved in `rawBytes`
    /// (docs/CONFIG.md -> "One unknown key in an otherwise valid document").
    public static func parse(_ data: Data) throws -> ConfigDocument {
        let decoded = try JSONDecoder().decode(Fields.self, from: data)
        return ConfigDocument(
            rawBytes: data,
            version: decoded.version,
            issuedAt: decoded.issuedAt,
            notAfter: decoded.notAfter,
            apiBaseURL: decoded.apiBaseUrl,
            tier2OnDeviceLLM: decoded.tier2OnDeviceLLM,
            tier3CloudFallback: decoded.tier3CloudFallback,
            llmQuota: decoded.llmQuota,
            ocrConfidenceThreshold: decoded.ocrConfidenceThreshold,
            minSchemaVersion: decoded.minSchemaVersion,
            referencePacks: decoded.referencePacks,
            maintenance: decoded.maintenance,
            rolloutSalt: decoded.rolloutSalt,
            flags: decoded.flags ?? [:]
        )
    }

    /// The `Decodable` shadow of the public type. Kept separate so the public
    /// surface stays a plain value type with a `rawBytes` field that no decoder
    /// could populate.
    private struct Fields: Decodable {
        let version: Int
        let issuedAt: Date
        let notAfter: Date
        let apiBaseUrl: URL?
        let tier2OnDeviceLLM: Bool
        let tier3CloudFallback: Bool
        let llmQuota: LLMQuota
        let ocrConfidenceThreshold: Double
        let minSchemaVersion: Int
        let referencePacks: ReferencePacks
        let maintenance: MaintenanceNotice?
        let rolloutSalt: String
        let flags: [String: FeatureFlag]?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeFlexibleInt(forKey: .version)
            issuedAt = try container.decodeTimestamp(forKey: .issuedAt)
            notAfter = try container.decodeTimestamp(forKey: .notAfter)
            apiBaseUrl = try container.decodeIfPresent(URL.self, forKey: .apiBaseUrl)
            tier2OnDeviceLLM = try container.decode(Bool.self, forKey: .tier2OnDeviceLLM)
            tier3CloudFallback = try container.decode(Bool.self, forKey: .tier3CloudFallback)
            llmQuota = try container.decode(LLMQuota.self, forKey: .llmQuota)
            ocrConfidenceThreshold = try container.decode(Double.self, forKey: .ocrConfidenceThreshold)
            minSchemaVersion = try container.decodeFlexibleInt(forKey: .minSchemaVersion)
            referencePacks = try container.decode(ReferencePacks.self, forKey: .referencePacks)
            rolloutSalt = try container.decode(String.self, forKey: .rolloutSalt)
            flags = try? container.decodeIfPresent([String: FeatureFlag].self, forKey: .flags)

            if let notice = try? container.decodeIfPresent(MaintenanceFields.self, forKey: .maintenance) {
                // An out-of-enum severity degrades to `.info` rather than
                // rejecting the document. Losing a whole document - possibly
                // carrying an urgent kill switch - over the styling of an
                // informational banner is the worse failure direction.
                maintenance = MaintenanceNotice(
                    text: notice.text,
                    severity: MaintenanceNotice.Severity(rawValue: notice.severity) ?? .info,
                    until: notice.until
                )
            } else {
                maintenance = nil
            }
        }

        enum CodingKeys: String, CodingKey {
            case version, issuedAt, notAfter, apiBaseUrl, tier2OnDeviceLLM, tier3CloudFallback
            case llmQuota, ocrConfidenceThreshold, minSchemaVersion, referencePacks
            case maintenance, rolloutSalt, flags
        }
    }

    private struct MaintenanceFields: Decodable {
        let text: String
        let severity: String
        let until: Date

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            severity = try container.decode(String.self, forKey: .severity)
            until = try container.decodeTimestamp(forKey: .until)
        }

        enum CodingKeys: String, CodingKey {
            case text, severity, until
        }
    }
}

// MARK: - Decoding helpers

private extension KeyedDecodingContainer {
    /// Decodes an integer that may legally arrive in exponent form.
    ///
    /// `1e3` is a valid JSON number and a valid JSON Schema `integer`, and the
    /// server's canonicalizer preserves that token verbatim - so a document can
    /// genuinely carry `"cloudFallback": 1e3`. A plain `decode(Int.self)` fails
    /// on it, which would reject an entirely valid document.
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        let double = try decode(Double.self, forKey: key)
        guard double.rounded() == double, double.magnitude < 9.007_199_254_740_992e15 else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "Expected an integer, found \(double)."
            )
        }
        return Int(double)
    }

    /// Decodes an ISO-8601 UTC timestamp, with or without fractional seconds.
    ///
    /// Not `JSONDecoder.dateDecodingStrategy`, because that would apply to every
    /// date in the document and this type also decodes non-date fields through
    /// the same decoder.
    func decodeTimestamp(forKey key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        // Constructed per call rather than cached in a static: ISO8601DateFormatter
        // is not Sendable, and config parsing is rare enough (once per fetch or
        // cache read) that a shared instance would buy nothing.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self, debugDescription: "Not an ISO-8601 timestamp: \(text)"
        )
    }
}
