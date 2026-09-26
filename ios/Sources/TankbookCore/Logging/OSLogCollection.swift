import Foundation

/// The collected-log constants (docs/LOGGING.md §5 and docs/PRACTICES.md §6,
/// tier C - compiled constant, one definition, named).
public enum DiagnosticsLogConstants {
    /// The `live.belyaev.tankbook` subsystem every OSLog line rides
    /// (docs/LOGGING.md §4).
    public static let subsystem = "live.belyaev.tankbook"

    /// The §5 window: the last 24 h of INFO+ entries. A compiled constant with
    /// a doc twin (docs/PRACTICES.md: "time windows in days are user-visible
    /// promises" - §5's copy says "last 24 hours", so the number is meaning, not
    /// tuning, and a change is a review + doc change, never a config edit).
    public static let logWindow: TimeInterval = 24 * 60 * 60

    /// The most log lines the bundle may hold. Compiled: it bounds the text a
    /// user previews and sends, so it must not grow silently with tuning, and
    /// it keeps the export bounded in size, not O(entries) (docs/LOGGING.md
    /// §7 volume discipline).
    public static let logEntryCap = 5_000

    /// How long a day file of the on-disk log (`FileLogStore`) is kept: two
    /// days, so the 24 h window is always whole whatever the time of day.
    public static let fileRetention: TimeInterval = 2 * 24 * 60 * 60

    /// The most bytes one day file may grow to. A day past it keeps its first
    /// lines and drops the rest rather than grow the device's storage.
    public static let fileDayByteCap = 4 * 1_024 * 1_024
}

/// One entry read back from the stored log: when it happened and the text that
/// was kept for it. The text is the sink's own rendered line; it is NOT
/// trusted as redacted - `OSLogTextRedactor` re-scrubs it before the bundle
/// holds it (docs/LOGGING.md §1: never trust a line because storage held it).
public struct OSLogCollectedEntry: Sendable, Equatable {
    public let date: Date
    public let text: String

    public init(date: Date, text: String) {
        self.date = date
        self.text = text
    }
}

/// The seam between the collector and the stored log, so the 24 h window is
/// deterministic under test (docs/TESTING.md: mock the boundary, don't boot the
/// world). The production reader is `FileLogStore`; L1 drives this protocol's
/// throw and content directly.
public protocol OSLogEntryReading: Sendable {
    /// This app's own INFO+ entries under `subsystem` dated at or after `since`,
    /// newest-capped at `limit`, returned oldest-first. Throws when the store is
    /// unreadable - the caller treats that as a degraded bundle, never an error.
    func readInfoPlus(subsystem: String, since: Date, limit: Int) throws -> [OSLogCollectedEntry]
}

/// Re-scrubs a stored log line before the bundle holds it
/// (docs/LOGGING.md §1, hard rule 12). The sink normally only ever persists
/// already-redacted text, so this is a no-op on a clean line - but a debug
/// reveal build or a future sink bug could persist a real Sensitive value, and
/// the collector cannot reconstruct the line's original classification from
/// opaque text. The only signal it has is the field *name*, so the value of any
/// field whose name is a known Sensitive carrier is masked here - the belt and
/// braces behind the sink's own guarantee. A value that contains spaces leaks
/// as trailing space-split words that no text-based scrubber can attribute;
/// that is accepted because the real defense is the sink (the file sink never
/// reveals a Sensitive value, in any build).
public enum OSLogTextRedactor {
    /// Field names under which a Sensitive-class value can ride in this app's
    /// typed events (docs/LOGGING.md §1 examples; the `LogEvents`/test
    /// vocabularies). Over-masking one of these on a clean line is at worst a
    /// `<redacted>` in a debug-only export; under-masking is a leak.
    static let sensitiveFieldNames: Set<String> = [
        "stationName", "station", "brand", "vendor", "provider",
        "note", "notes", "plate", "amount", "volumeL", "unitPrice",
        "price", "odometer", "latitude", "longitude", "email", "replyTo",
        "deviceModel", "errorDescription", "underlyingError"
    ]
    /// Masks every `name=value` token whose name is a Sensitive carrier.
    /// Tokens that do not carry an `=` cannot exist on a Safe line (Safe values
    /// never contain spaces), so any such token directly after a masked value is
    /// that value's leaked space-split tail and is dropped too.
    public static func redact(_ line: String) -> String {
        var out: [String] = []
        out.reserveCapacity(line.count / 2)
        var inMaskedValue = false
        for token in line.split(separator: " ") {
            if let equals = token.firstIndex(of: "=") {
                let name = String(token[..<equals])
                if sensitiveFieldNames.contains(name) {
                    out.append("\(name)=<redacted>")
                    inMaskedValue = true
                } else {
                    out.append(String(token))
                    inMaskedValue = false
                }
            } else if inMaskedValue {
                // The space-split tail of a masked value; drop it.
                continue
            } else {
                out.append(String(token))
            }
        }
        return out.joined(separator: " ")
    }
}
