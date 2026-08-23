import Foundation

/// The opt-in "Attach diagnostics" bundle from docs/LOGGING.md §5: recent
/// breadcrumbs plus app/device metadata, already run through the same redactor,
/// ready to be previewed and sent from the About screen. No UI here - this is
/// the data assembly only.
public struct DiagnosticsBundle: Sendable, Equatable {
    public let generatedAt: Date
    public let appVersion: String
    public let platform: String
    public let deviceId: String?
    /// The redacted breadcrumb lines, oldest first.
    public let breadcrumbs: [String]

    /// The full, redacted diagnostics text. The user previews exactly this
    /// before it leaves the device (docs/LOGGING.md §5: never silent).
    public func rendered() -> String {
        var lines: [String] = []
        lines.append("Tankbook diagnostics")
        lines.append("generatedAt=\(LogRenderer.timestamp(generatedAt))")
        lines.append("appVersion=\(appVersion)")
        lines.append("platform=\(platform)")
        if let deviceId {
            lines.append("deviceId=\(deviceId)")
        }
        lines.append("breadcrumbCount=\(breadcrumbs.count)")
        lines.append("--- breadcrumbs ---")
        lines.append(contentsOf: breadcrumbs)
        return lines.joined(separator: "\n")
    }

    /// UTF-8 data of `rendered()`.
    public var data: Data { Data(rendered().utf8) }
}

public enum DiagnosticsExport {
    /// Assembles a bundle from a log instance's breadcrumb ring and the current
    /// log context. Every line is re-rendered with the same redactor, so the
    /// bundle contains no Sensitive/Never value even if a breadcrumb was
    /// recorded in a debug build.
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
}
