import Foundation
import os

/// Where a redacted `LogLine` goes. Every sink receives lines that have
/// already passed through the redactor, so a sink can never emit a `never`
/// value and - in release builds - never a `sensitive` value either.
public protocol LogSink: Sendable {
    func emit(_ line: LogLine)
}

/// Production sink: writes the redacted line to `os.Logger` under the
/// `live.belyaev.tankbook` subsystem (docs/LOGGING.md §4). Console.app and
/// `log collect` reach it with no logging SDK.
///
/// The sink only ever receives content that has survived the redactor - Never
/// values are dropped in every build and Sensitive values in release builds -
/// so every interpolation emitted here is Safe-class content, and `.public` is
/// used only on Safe values (the classifier's `.private` route is exercised in
/// debug builds, where the line's Sensitive fields are rendered as
/// `<redacted>` unless the debug opt-in is set).
public struct OSLogSink: LogSink {
    public let subsystem: String
    /// Explicit debug opt-in from docs/LOGGING.md §1: when true, debug builds
    /// reveal sensitive values in the emitted text. Never set in production;
    /// the value is redacted again by OSLog's privacy handling when the
    /// unified log persists it.
    public let revealSensitiveInDebug: Bool

    public init(subsystem: String = "live.belyaev.tankbook", revealSensitiveInDebug: Bool = false) {
        self.subsystem = subsystem
        self.revealSensitiveInDebug = revealSensitiveInDebug
    }

    public func emit(_ line: LogLine) {
        // The redactor has already dropped Never values (all builds) and
        // Sensitive values (release builds). What remains is Safe-class
        // content, so a single `.public` interpolation is correct: only Safe
        // values are ever marked `.public`.
        #if DEBUG
        let text = LogRenderer.render(line, revealSensitive: revealSensitiveInDebug)
        #else
        let text = LogRenderer.render(line, revealSensitive: false)
        #endif
        let logger = Logger(subsystem: subsystem, category: line.category.rawValue)
        logger.log(level: line.level.osLogType, "\(text, privacy: .public)")
    }
}

/// Test/export sink: accumulates redacted lines in memory so tests assert on
/// real emitted output instead of on a mock having been called
/// (docs/TESTING.md, "mock the boundary, don't boot the world").
public final class InMemorySink: LogSink, @unchecked Sendable {
    private struct State {
        var lines: [LogLine] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func emit(_ line: LogLine) {
        lock.withLock { state in
            state.lines.append(line)
        }
    }

    /// Snapshot of every recorded line, oldest first.
    public func all() -> [LogLine] {
        lock.withLock { state in state.lines }
    }

    /// Every recorded line rendered to text with sensitive values masked.
    public func rendered() -> [String] {
        all().map { LogRenderer.render($0, revealSensitive: false) }
    }
}

extension LogLevel {
    /// Mapping onto `OSLogType`. There is no OSLog `warn`; handled degradation
    /// lands on `.error` so it is visible in Console.app, and true failures on
    /// `.fault` (docs/LOGGING.md §3 level discipline).
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .error
        case .error: return .fault
        }
    }
}
