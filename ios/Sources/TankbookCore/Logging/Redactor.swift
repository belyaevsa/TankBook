import Foundation

// MARK: - Privacy classification (docs/LOGGING.md §1)

/// The three privacy classes from docs/LOGGING.md §1. Every value that reaches
/// a log line is one of these three - there is no unclassified string path.
public enum LogValue: Sendable, Equatable {
    /// Safe - entity ids (UUIDs), entityType, schemaVersion, counts, byte
    /// sizes, durations, HTTP status, error codes, JSON pointers, field *names*.
    /// Logged freely, at any level.
    case safe(String)
    /// Sensitive - station and vendor names, notes, plate, monetary amounts,
    /// volumes, odometer, coordinates, filenames, email. Dropped by the
    /// redactor in release builds; in debug builds it travels only as
    /// `.private` (masked by every text renderer).
    case sensitive(String)
    /// Never - payload bodies, blob bytes, images, OCR text, tokens, API keys,
    /// presigned URLs. Dropped by the redactor in every build; the value never
    /// reaches any sink.
    case never(String)
}

/// A single classified name-value pair on a log line. The only construction
/// paths are the `LogField.safe/.sensitive/.never` factories, so a call site
/// must classify every value it logs.
public struct LogField: Sendable, Equatable {
    public let name: String
    public let value: LogValue

    public init(name: String, value: LogValue) {
        self.name = name
        self.value = value
    }
}

extension LogField {
    /// Safe-class field. Prefer the concrete `String` overload; the generic
    /// form exists for `Int`, `Double`, `UUID` and other `CustomStringConvertible`
    /// values.
    public static func safe(_ name: String, _ value: String) -> LogField {
        LogField(name: name, value: .safe(value))
    }

    public static func safe(_ name: String, _ value: some CustomStringConvertible) -> LogField {
        LogField(name: name, value: .safe(value.description))
    }

    /// Sensitive-class field: masked in every text renderer, `.private` to
    /// OSLog in debug builds, dropped in release builds.
    public static func sensitive(_ name: String, _ value: String) -> LogField {
        LogField(name: name, value: .sensitive(value))
    }

    public static func sensitive(_ name: String, _ value: some CustomStringConvertible) -> LogField {
        LogField(name: name, value: .sensitive(value.description))
    }

    /// Never-class field: dropped before any sink in every build. The value is
    /// accepted (and documented) so a call site can hand over whatever it
    /// holds; the redactor guarantees it is never emitted.
    public static func never(_ name: String, _ value: String) -> LogField {
        LogField(name: name, value: .never(value))
    }

    public static func never(_ name: String, _ value: some CustomStringConvertible) -> LogField {
        LogField(name: name, value: .never(value.description))
    }
}

// MARK: - Redactor (the enforcement point)

/// How a field survives redaction and is emitted.
public enum RenderKind: Sendable, Equatable {
    /// Safe-class content: emitted verbatim, `.public` to OSLog.
    case publicValue(String)
    /// Sensitive-class content: `.private` to OSLog in debug builds, replaced
    /// by `<redacted>` in every text renderer, dropped in release builds.
    case privateValue(String)
}

/// A redacted name-value pair ready for a sink.
public struct RenderField: Sendable, Equatable {
    public let name: String
    public let kind: RenderKind
}

/// The single enforcement point for the privacy classes (docs/LOGGING.md §1
/// and hard rule 12). Every `LogLine` passes through `Redactor.redact` before
/// any sink sees it, so the classification cannot be bypassed at a call site.
public struct Redactor: Sendable {
    public static let shared = Redactor()

    public init() {}

    /// Applies the classification:
    /// - `safe` -> `.publicValue`
    /// - `sensitive` -> `.privateValue` in debug builds, **dropped** in release
    /// - `never` -> **dropped** in every build
    public func redact(_ fields: [LogField]) -> [RenderField] {
        fields.compactMap { field in
            switch field.value {
            case .safe(let value):
                return RenderField(name: field.name, kind: .publicValue(value))
            case .sensitive(let value):
                #if DEBUG
                return RenderField(name: field.name, kind: .privateValue(value))
                #else
                return nil
                #endif
            case .never:
                return nil
            }
        }
    }
}

// MARK: - Log line

/// A fully-assembled, redacted log line. `fields` contains no `never` value in
/// any build and no `sensitive` value in release builds.
public struct LogLine: Sendable, Equatable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let event: String
    public let traceId: UUID?
    public let deviceId: String?
    public let appVersion: String
    public let platform: String
    public let fields: [RenderField]

    /// Plain-text rendering with sensitive values masked (never values are
    /// already absent from `fields`). Used by the in-memory sink, the
    /// breadcrumb ring and the diagnostics export - the one renderer that
    /// produces output meant to leave the process.
    public var redactedDescription: String {
        LogRenderer.render(self, revealSensitive: false)
    }
}

/// Renders a redacted `LogLine` to a single deterministic text line:
/// `timestamp LEVEL [category] event=... traceId=... deviceId=... appVersion=... platform=... field=value ...`
public enum LogRenderer {
    /// Renders a line. `revealSensitive` is the explicit opt-in flag from
    /// docs/LOGGING.md §1 (debug-only); the default masks every sensitive
    /// value. `never` values cannot be revealed - they are absent from
    /// `LogLine.fields` in every build.
    public static func render(_ line: LogLine, revealSensitive: Bool = false) -> String {
        var parts: [String] = []
        parts.append(timestamp(line.timestamp))
        parts.append(line.level.rawValue.uppercased())
        parts.append("[\(line.category.rawValue)]")
        parts.append("event=\(line.event)")
        if let traceId = line.traceId {
            parts.append("traceId=\(traceId.uuidString)")
        }
        if let deviceId = line.deviceId {
            parts.append("deviceId=\(deviceId)")
        }
        parts.append("appVersion=\(line.appVersion)")
        parts.append("platform=\(line.platform)")
        for field in line.fields {
            switch field.kind {
            case .publicValue(let value):
                parts.append("\(field.name)=\(value)")
            case .privateValue(let value):
                if revealSensitive {
                    parts.append("\(field.name)=\(value)")
                } else {
                    parts.append("\(field.name)=<redacted>")
                }
            }
        }
        return parts.joined(separator: " ")
    }

    /// ISO-8601 UTC with fractional seconds - deterministic across locales.
    public static func timestamp(_ date: Date) -> String {
        date.ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
    }
}
