import Foundation
import os

/// One entry in the breadcrumb ring. It stores the already-redacted rendered
/// line, not the raw `LogLine`, so a Sensitive/Never value can never persist in
/// the ring itself (docs/LOGGING.md §5, §6: breadcrumbs ride crash reports).
public struct Breadcrumb: Sendable, Equatable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let event: String
    /// The fully redacted, rendered line. Sensitive values appear as
    /// `<redacted>`; never values are absent.
    public let rendered: String

    init(line: LogLine) {
        self.timestamp = line.timestamp
        self.level = line.level
        self.category = line.category
        self.event = line.event
        self.rendered = LogRenderer.render(line, revealSensitive: false)
    }
}

/// A bounded, thread-safe, in-memory ring of the most recent events
/// (~50 entries, docs/LOGGING.md §4-§5). Oldest entries are evicted first;
/// reading returns a snapshot.
public final class Breadcrumbs: @unchecked Sendable {
    public static let defaultCapacity = 50

    public let capacity: Int

    private struct State {
        var entries: [Breadcrumb] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init(capacity: Int = Breadcrumbs.defaultCapacity) {
        precondition(capacity > 0, "breadcrumb capacity must be positive")
        self.capacity = capacity
    }

    /// Records a redacted line, evicting the oldest when at capacity.
    public func record(_ line: LogLine) {
        let crumb = Breadcrumb(line: line)
        lock.withLock { state in
            state.entries.append(crumb)
            if state.entries.count > capacity {
                state.entries.removeFirst(state.entries.count - capacity)
            }
        }
    }

    /// Snapshot of the current contents, oldest first. Safe under concurrent
    /// appends.
    public func snapshot() -> [Breadcrumb] {
        lock.withLock { state in state.entries }
    }
}
