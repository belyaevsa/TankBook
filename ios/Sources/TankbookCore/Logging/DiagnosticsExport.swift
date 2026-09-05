import Foundation

/// The opt-in "Attach diagnostics" bundle from docs/LOGGING.md §5: the last 24 h
/// of the app's own INFO+ entries (breadcrumb ring, plus the OSLog window when
/// the store is readable), run through the same redactor, alongside app/device
/// metadata, the persisted sync state and per-table DB row counts. No UI here -
/// this is the data assembly only. The user previews exactly `rendered()` before
/// anything leaves the device (§5: never silent).
public struct DiagnosticsBundle: Sendable, Equatable {
    public let generatedAt: Date
    public let appVersion: String
    public let platform: String
    public let deviceId: String?
    /// The redacted breadcrumb-ring lines, oldest first. The ring is the
    /// in-memory fallback that covers what OSLog may have dropped; every line
    /// was rendered by `LogRenderer` with sensitive values masked.
    public let breadcrumbs: [String]
    /// The redacted 24 h OSLog window, oldest first. Every line was re-scrubbed
    /// by `OSLogTextRedactor` before it was held, exactly as the ring lines
    /// were - no line is trusted because OSLog produced it (hard rule 12).
    public let osLogLines: [String]
    /// Whether the 24 h OSLog window was readable. `unavailable` is a degraded
    /// bundle, not an error: the ring is the fallback and the marker tells
    /// support a quiet device (`ok lines=0`) from a missing capability.
    public let logStore: LogStoreState
    /// The persisted sync state (OB.3) plus the derived queue counts - nothing
    /// beyond what docs/LOGGING.md §5 lists, all Safe-class (hard rule 12).
    public let sync: DiagnosticsSyncSummary?
    /// Physical row counts per table (`Repository.rowCount`), counts only.
    public let rowCounts: [String: Int]

    public init(generatedAt: Date,
                appVersion: String,
                platform: String,
                deviceId: String?,
                breadcrumbs: [String],
                osLogLines: [String] = [],
                logStore: LogStoreState = .unavailable,
                sync: DiagnosticsSyncSummary? = nil,
                rowCounts: [String: Int] = [:]) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.platform = platform
        self.deviceId = deviceId
        self.breadcrumbs = breadcrumbs
        self.osLogLines = osLogLines
        self.logStore = logStore
        self.sync = sync
        self.rowCounts = rowCounts
    }

    /// The full, redacted diagnostics text. The user previews exactly this
    /// before it leaves the device (docs/LOGGING.md §5: never silent). The line
    /// shape is `key=value` throughout, matching `LogRenderer`'s own lines.
    public func rendered() -> String {
        var lines: [String] = []
        lines.append("Tankbook diagnostics")
        lines.append("generatedAt=\(LogRenderer.timestamp(generatedAt))")
        lines.append("appVersion=\(appVersion)")
        lines.append("platform=\(platform)")
        if let deviceId {
            lines.append("deviceId=\(deviceId)")
        }
        switch logStore {
        case .ok(let count):
            lines.append("logStore=ok lines=\(count)")
        case .unavailable:
            lines.append("logStore=unavailable")
        }
        lines.append("breadcrumbCount=\(breadcrumbs.count)")
        lines.append("--- log ---")
        lines.append(contentsOf: breadcrumbs)
        lines.append(contentsOf: osLogLines)
        if let sync {
            lines.append("--- sync ---")
            if let lastSuccessAt = sync.lastSuccessAt {
                lines.append("lastSuccessAt=\(LogRenderer.timestamp(lastSuccessAt))")
            }
            lines.append("dirtyCount=\(sync.dirtyCount)")
            lines.append("flaggedCount=\(sync.flaggedCount)")
            if let failure = sync.lastFailure {
                lines.append("lastFailureAt=\(LogRenderer.timestamp(failure.at))")
                lines.append("lastFailureKind=\(failure.kind.rawValue)")
                if let code = failure.code {
                    lines.append("lastFailureCode=\(code)")
                }
                if let traceId = failure.traceId {
                    lines.append("lastFailureTraceId=\(traceId)")
                }
            }
        }
        if !rowCounts.isEmpty {
            lines.append("--- row counts ---")
            for table in rowCounts.keys.sorted() {
                lines.append("rowCount.\(table)=\(rowCounts[table] ?? 0)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// UTF-8 data of `rendered()`.
    public var data: Data { Data(rendered().utf8) }
}

/// The device's 24 h OSLog window state in the bundle: `ok` with the number of
/// collected lines, or `unavailable` when reading failed (permissions, simulator,
/// an unreadable store). A readable-but-silent store is `ok lines=0` - that is
/// how support tells a quiet device from a missing capability.
public enum LogStoreState: Sendable, Equatable {
    case ok(lineCount: Int)
    case unavailable
}

/// What the bundle carries about sync (docs/LOGGING.md §5, OB.3): the persisted
/// last success and last failure (kind + code + traceId - the traceId maps a
/// report to the server's own lines, §2) plus the derived queue counts. Every
/// field is Safe-class; a domain value has no route here (hard rule 12).
public struct DiagnosticsSyncSummary: Sendable, Equatable {
    public let lastSuccessAt: Date?
    public let dirtyCount: Int
    public let flaggedCount: Int
    public let lastFailure: SyncFailureRecord?

    public init(lastSuccessAt: Date?, dirtyCount: Int, flaggedCount: Int,
                lastFailure: SyncFailureRecord?) {
        self.lastSuccessAt = lastSuccessAt
        self.dirtyCount = dirtyCount
        self.flaggedCount = flaggedCount
        self.lastFailure = lastFailure
    }
}

public enum DiagnosticsExport {
    /// Assembles a bundle from a log instance's breadcrumb ring and the current
    /// log context, without reading OSLog (the factory the ring-only callers and
    /// tests use; the log window is left `unavailable`). Every line is
    /// re-rendered with the same redactor, so the bundle contains no
    /// Sensitive/Never value even if a breadcrumb was recorded in a debug build.
    public static func make(log: TankbookLog, context: LogContext) -> DiagnosticsBundle {
        let crumbs = (log.breadcrumbs?.snapshot() ?? []).map(\.rendered)
        return DiagnosticsBundle(generatedAt: Date(),
                                 appVersion: context.appVersion,
                                 platform: context.platform,
                                 deviceId: context.deviceId,
                                 breadcrumbs: crumbs)
    }

    /// Assembles a bundle from an explicit breadcrumb ring (tests, tools).
    public static func make(breadcrumbs: Breadcrumbs, context: LogContext) -> DiagnosticsBundle {
        make(lines: breadcrumbs.snapshot().map(\.rendered), context: context)
    }

    /// Assembles a bundle from already-rendered redacted lines.
    public static func make(lines: [String], context: LogContext) -> DiagnosticsBundle {
        DiagnosticsBundle(generatedAt: Date(),
                          appVersion: context.appVersion,
                          platform: context.platform,
                          deviceId: context.deviceId,
                          breadcrumbs: lines)
    }

    /// The full assembly behind About's "Attach diagnostics" (docs/LOGGING.md
    /// §5): the breadcrumb ring merged with the last 24 h of this app's own
    /// OSLog window, plus the sync summary and the row counts. When `osLog` is
    /// nil or its read throws, the bundle degrades to the ring alone and marks
    /// `logStore=unavailable` - a degraded bundle, never an error. Every
    /// collected OSLog line is re-scrubbed by the OSLog redactor before it is
    /// held, exactly as the ring lines are: a line is never trusted because
    /// OSLog produced it (docs/LOGGING.md §1).
    public static func collect(log: TankbookLog,
                               context: LogContext,
                               osLog: (any OSLogEntryReading)?,
                               sync: DiagnosticsSyncSummary?,
                               rowCounts: [String: Int],
                               now: Date = Date()) -> DiagnosticsBundle {
        let crumbs = (log.breadcrumbs?.snapshot() ?? []).map(\.rendered)
        return assemble(breadcrumbLines: crumbs, context: context, osLog: osLog,
                        sync: sync, rowCounts: rowCounts, now: now)
    }

    /// Assembles a bundle from already-rendered ring lines (the snapshot is
    /// taken by the caller so the OSLog read can run off the main actor). Same
    /// contract as `collect(log:...)`: the collected OSLog lines are re-scrubbed
    /// before they are held, and an unreadable store degrades to the ring.
    public static func assemble(breadcrumbLines: [String],
                                context: LogContext,
                                osLog: (any OSLogEntryReading)?,
                                sync: DiagnosticsSyncSummary?,
                                rowCounts: [String: Int],
                                now: Date = Date()) -> DiagnosticsBundle {
        var logStore = LogStoreState.unavailable
        var osLogLines: [String] = []
        if let osLog {
            do {
                let entries = try osLog.readInfoPlus(
                    subsystem: DiagnosticsLogConstants.subsystem,
                    since: now.addingTimeInterval(-DiagnosticsLogConstants.logWindow),
                    limit: DiagnosticsLogConstants.osLogEntryCap)
                osLogLines = entries.map { OSLogTextRedactor.redact($0.text) }
                logStore = .ok(lineCount: osLogLines.count)
            } catch {
                logStore = .unavailable
            }
        }
        return DiagnosticsBundle(generatedAt: now,
                                 appVersion: context.appVersion,
                                 platform: context.platform,
                                 deviceId: context.deviceId,
                                 breadcrumbs: breadcrumbLines,
                                 osLogLines: osLogLines,
                                 logStore: logStore,
                                 sync: sync,
                                 rowCounts: rowCounts)
    }
}
