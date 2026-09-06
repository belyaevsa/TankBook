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
/// The notification-response replay launch hooks (PJ.5 for the tap, RV.78 for
/// the banner actions): drive a notification response without a real
/// notification, so the L4 suites and the simctl-driven screenshots exercise
/// the exact response path. Two shapes:
///
/// - `-replayNotificationResponse <identifier>` - a plain tap (the default
///   action).
/// - `-replayNotificationAction <complete|snooze> <identifier>` - one of the
///   two banner actions.
///
/// The identifier is the request identifier the seeded reminder was scheduled
/// under (`reminder.<id>.<kind>`); the action token is the `ReminderBannerAction`
/// case name so a test never spells the platform string. Compiled out of
/// release builds: this cannot ship.
enum NotificationResponseReplay {
    struct Request {
        var actionIdentifier: String?
        var requestIdentifier: String
    }

    static func request(arguments: [String] = ProcessInfo.processInfo.arguments) -> Request? {
        if let index = arguments.firstIndex(of: "-replayNotificationResponse"),
           arguments.indices.contains(index + 1) {
            return Request(actionIdentifier: nil, requestIdentifier: arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "-replayNotificationAction"),
           arguments.indices.contains(index + 1),
           arguments.indices.contains(index + 2) {
            let token = arguments[index + 1]
            let actionID = ReminderBannerAction(rawValue: token)
                ?? ReminderBannerAction(rawValue: "reminder.action.\(token)")
            return Request(actionIdentifier: actionID?.rawValue,
                           requestIdentifier: arguments[index + 2])
        }
        return nil
    }
}

/// Drives a replayed notification response (a tap, or a banner action) through
/// the notification delegate's own `handle` at launch - the same decision path
/// a real `didReceive` response takes - so the L4 replay cannot drift from the
/// shipped behavior. Kept out of `TabRoots` so a DEBUG hook costs the launch
/// path one call.
enum NotificationReplayDriver {
    @MainActor
    static func driveIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let replay = NotificationResponseReplay.request(arguments: arguments) else { return }
        UNNotificationScheduler.replayForTests(actionIdentifier: replay.actionIdentifier,
                                               requestIdentifier: replay.requestIdentifier)
    }
}
#endif
