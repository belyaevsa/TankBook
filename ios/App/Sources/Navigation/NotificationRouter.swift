import Foundation
import Observation
import TankbookCore

/// Drives the navigation a tapped notification asks for (PJ.5,
/// docs/SCREENMAP.md -> the deep link). The `NotificationDelegate` resolves a
/// tapped identifier to a `NotificationRoute` and hands it here; `AppRootView`
/// observes `pending` and performs the actual tab switch / push, then consumes
/// the request. Held as a reference type (not the view itself) because the
/// delegate - a background-thread singleton - captures it, and the view reads
/// it: that is how a platform tap reaches SwiftUI state.
@MainActor
@Observable
final class NotificationRouter {
    /// A resolved tap waiting to drive navigation. Exactly one navigation drive
    /// consumes it.
    enum Request: Equatable {
        /// Land on the Reminders screen with this reminder's completion flow
        /// surfaced.
        case openRemindersFor(UUID)
        /// Land on the Trends tab root.
        case openTrends
    }

    private(set) var pending: Request?

    /// The single translation from a core route to an app navigation request.
    /// `.none` is deliberately swallowed: an unknown or malformed identifier
    /// opens the app normally and routes nowhere (hard rule 7 - a stale
    /// notification is not a dead end, and never a detour).
    func handle(_ route: NotificationRoute) {
        switch route {
        case .reminder(let id): pending = .openRemindersFor(id)
        case .trends: pending = .openTrends
        case .none: break
        }
    }

    /// Reads and clears in one step: a request is consumed by exactly one drive.
    func consume() -> Request? {
        defer { pending = nil }
        return pending
    }
}

#if DEBUG
/// The `-replayNotificationResponse <identifier>` launch hook (PJ.5): drives a
/// notification tap without a real notification, so the L4 suites and the
/// simctl-driven screenshots exercise the exact `didReceive` path - resolve
/// through the same core mapping, forward through the same router. Compiled
/// out of release builds: this cannot ship.
enum NotificationResponseReplay {
    static func identifier(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: "-replayNotificationResponse"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
