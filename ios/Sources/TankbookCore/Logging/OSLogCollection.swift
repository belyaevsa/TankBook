import Foundation
import OSLog
import os

/// The collected-log constants (docs/LOGGING.md §5 and docs/PRACTICES.md §6,
/// tier C - compiled constant, one definition, named).
public enum DiagnosticsLogConstants {
    /// The `live.belyaev.tankbook` subsystem every OSLog line rides
    /// (docs/LOGGING.md §4) - the exact predicate the diagnostics window reads.
    public static let subsystem = "live.belyaev.tankbook"

    /// The §5 window: the last 24 h of INFO+ entries. A compiled constant with
    /// a doc twin (docs/PRACTICES.md: "time windows in days are user-visible
    /// promises" - §5's copy says "last 24 hours", so the number is meaning, not
    /// tuning, and a change is a review + doc change, never a config edit).
    public static let logWindow: TimeInterval = 24 * 60 * 60

    /// The most OSLog lines the bundle may hold. Compiled: it bounds the text a
    /// user previews and shares, so it must not grow silently with tuning, and
    /// it keeps the export O(1) in bundle size, not O(entries) (docs/LOGGING.md
    /// §7 volume discipline). The ring is capped at ~50 on top of this.
    public static let osLogEntryCap = 200
}

/// One entry collected from the unified log: when it happened and the text
/// OSLog persisted for it. The text is the sink's own rendered line; it is NOT
/// trusted as redacted - `OSLogTextRedactor` re-scrubs it before the bundle
/// holds it (docs/LOGGING.md §1: never trust a line because OSLog produced it).
public struct OSLogCollectedEntry: Sendable, Equatable {
    public let date: Date
    public let text: String

    public init(date: Date, text: String) {
        self.date = date
        self.text = text
    }
}

/// The seam between the collector and the unified log, so the 24 h window is
/// deterministic under test (docs/TESTING.md: mock the boundary, don't boot the
/// world). The production reader is `OSLogStoreEntryReader`; L1 drives this
/// protocol's throw and content directly.
public protocol OSLogEntryReading: Sendable {
    /// This app's own INFO+ entries under `subsystem` dated at or after `since`,
    /// newest-capped at `limit`, returned oldest-first. Throws when the store is
    /// unavailable (permissions, simulator, a private store) - the caller treats
    /// that as a degraded bundle, never an error.
    func readInfoPlus(subsystem: String, since: Date, limit: Int) throws -> [OSLogCollectedEntry]
}

/// Reads the unified log for the current process's own entries
/// (docs/LOGGING.md §4-§5). `OSLogStore` reaches only what this process logged,
/// which is exactly the `live.belyaev.tankbook` subsystem - the app logs only
/// through the `TankbookLog` facade, so the subsystem is the correct predicate.
/// May legitimately fail (a simulator, tightened permissions): the collector
/// degrades to the breadcrumb ring and marks `logStore=unavailable`.
public struct OSLogStoreEntryReader: OSLogEntryReading {
    public init() {}

    public func readInfoPlus(subsystem: String, since: Date, limit: Int) throws -> [OSLogCollectedEntry] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let start = store.position(date: since)
        var matched: [OSLogCollectedEntry] = []
        // `.reverse` enumerates newest-first back to the window start, so the
        // cap keeps the newest `limit` lines and the array is reversed to
        // chronological order at the end. The position is a bound, not an exact
        // cursor, so each entry is also date-filtered against the window.
        let entries = try store.getEntries(with: [.reverse], at: start, matching: nil)
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            guard log.subsystem == subsystem else { continue }
            guard log.date >= since else { continue }
            guard Self.acceptedLevels.contains(log.level) else { continue }
            matched.append(OSLogCollectedEntry(date: log.date, text: log.composedMessage))
            if matched.count >= limit { break }
        }
        return matched.reversed()
    }

    /// INFO+ only, docs/LOGGING.md §5. `debug` is not persisted by default and
    /// is excluded anyway - the diagnostics bundle is a §5 INFO+ surface.
    private static let acceptedLevels: Set<OSLogEntryLog.Level> = [.info, .notice, .error, .fault]
}

/// Re-scrubs a collected OSLog line before the bundle holds it
/// (docs/LOGGING.md §1, hard rule 12). The sink normally only ever persists
/// already-redacted text, so this is a no-op on a clean line - but a debug
/// reveal build or a future sink bug could persist a real Sensitive value, and
/// the collector cannot reconstruct the line's original classification from
/// opaque text. The only signal it has is the field *name*, so the value of any
/// field whose name is a known Sensitive carrier is masked here - the belt and
/// braces behind the sink's own guarantee. A value that contains spaces leaks
/// as trailing space-split words that no text-based scrubber can attribute;
/// that is accepted because the real defense is the sink (a value only reaches
/// OSLog text at all in a debug reveal build).
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
