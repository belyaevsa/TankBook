import Foundation
import Observation

/// App-level transient notices, owned by `AppRootView` and injected via the
/// environment. The one consumer today is the Edit entry delta toast
/// (docs/ERRORS.md -> Edit entry, row 4): an edit that shifts consumption posts
/// the message on save; Home sees the bumped `revision` and reloads so its
/// derived stats reflect the edit immediately (hard rule 2). `revision` also
/// bumps on deltas-less saves - an edit that moved nothing visible still
/// changed the data, and Home must not show stale rows.
@MainActor
@Observable
final class AppToastCenter {
    private(set) var message: String?
    private(set) var revision = 0
    private var dismissTask: Task<Void, Never>?

    /// Whether the auto-dismiss timer is parked. `-freezeToasts` (DEBUG) holds a
    /// toast on screen indefinitely so a screenshot can capture a message that
    /// would otherwise be gone in `visibility` seconds - the RV.149 receipt
    /// pose uses it. Production never passes the argument.
    private static let freezeForScreenshot: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-freezeToasts")
        #else
        false
        #endif
    }()

    /// Shows `message` for a few seconds. Any previous toast is replaced.
    func show(_ message: String) {
        self.message = message
        revision += 1
        guard !Self.freezeForScreenshot else { return }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.visibility)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// A save that produced no toast still touched the data: tell Home to
    /// recompute its derived stats.
    func noteEntryChanged() {
        revision += 1
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        message = nil
    }

    private static let visibility: UInt64 = 4_000_000_000
}
