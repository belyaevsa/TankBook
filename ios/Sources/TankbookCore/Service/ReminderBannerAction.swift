import Foundation

// MARK: - RV.78 the fired-reminder banner actions (docs/NOTIFICATIONS.md -> the actions)

/// The two things a fired reminder is for, as stable identifiers shared by
/// the registered category, the scheduled request's `categoryIdentifier`, and
/// the response parser. Raw strings because they cross the
/// `UserNotifications` boundary as the `UNNotificationAction` identifier and
/// the response's `actionIdentifier`; they live in core so the app's
/// registration and the response parser cannot drift - the same reason
/// `ReminderNotification.identifier` lives in core (docs/SCREENMAP.md -> the
/// deep link).
public enum ReminderBannerAction: String, Sendable, CaseIterable, Equatable {
    /// "Mark done": the user says the work is done. Deliberately NOT a silent
    /// `.done(nil)` here - the decision is to open the app on the completion
    /// sheet (design/screens/ReminderNotification.dc.html: "logging the cost
    /// stays a choice, never skipped for the user"). J7c makes declining the
    /// cost log first-class, but it has to be a choice the user made; a
    /// one-tap `.done(nil)` from a banner would skip the cost log without
    /// asking. The completion sheet is where that choice already lives, so
    /// this action lands exactly where a tap lands - there is no second
    /// completion implementation to drift from `ReminderLifecycle.complete`.
    case complete = "reminder.action.complete"
    /// "Push a week": defer the fired reminder by seven days and re-arm
    /// (`ReminderLifecycle.snooze`). The one action that needs no screen -
    /// the app handles it in the background and stays where it is
    /// (docs/NOTIFICATIONS.md -> the actions).
    case snooze = "reminder.action.snooze"

    /// The category identifier a reminder notification's request carries
    /// (`content.categoryIdentifier`), matching the registered category the
    /// app installs at launch.
    public static let categoryIdentifier = "reminder.actions"
}

/// What a response to a notification means, decided as a pure value so the
/// mapping tests as data (docs/TESTING.md L1) - the same split PJ.5
/// established for `NotificationRouteParser` (the app has no unit-test target;
/// anything in `ios/App` is only reachable by XCUITest, which asserts
/// behaviour and never values).
public enum NotificationActionDecision: Equatable, Sendable {
    /// A plain tap, or the "Mark done" action: drive the app wherever the
    /// request identifier promises (the Reminders screen with that reminder's
    /// completion sheet, or Trends for a monthly summary). Mark done does not
    /// complete silently - opening the sheet IS the decided behaviour, so the
    /// two responses share one path.
    case open(NotificationRoute)
    /// The "Push a week" action on a reminder: defer in place and re-arm. No
    /// screen is needed.
    case snooze(UUID)
    /// A dismissal, an unknown action, or an identifier this app cannot have
    /// produced: inert - the app opens normally and routes nowhere (hard rule
    /// 7: a stale notification must never dead-end, and never detour).
    case none
}

/// The pure action + identifier -> decision mapping (RV.78). The request
/// identifier resolves exactly as a tap does (`NotificationRouteParser`), then
/// the action decides what that resolution means: a default tap and Mark done
/// both OPEN the promised screen (the completion sheet for a reminder - see
/// `ReminderBannerAction.complete`); Push a week is a snooze; a dismissal or
/// an unrecognised action is inert. The platform's default/dismiss action ids
/// are named constants rather than an `import UserNotifications` dependency,
/// because core builds on macOS too.
public enum NotificationResponseParser {
    /// The platform's identifier for a plain tap on the notification body.
    public static let defaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
    /// The platform's identifier for the user dismissing the notification.
    public static let dismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

    public static func resolve(actionIdentifier: String?,
                               requestIdentifier: String) -> NotificationActionDecision {
        let route = NotificationRouteParser.resolve(identifier: requestIdentifier)

        switch actionIdentifier {
        case nil, defaultActionIdentifier, ReminderBannerAction.complete.rawValue:
            // A tap or "Mark done": open wherever the identifier promised. An
            // unresolvable identifier (a stale notification) is `.none`.
            guard route != .none else { return .none }
            return .open(route)
        case dismissActionIdentifier:
            // Swiping a banner away is not a request to open the app.
            return .none
        case ReminderBannerAction.snooze.rawValue:
            // Only a reminder notification can be pushed; a monthly summary
            // has no due to defer.
            guard case .reminder(let reminderID) = route else { return .none }
            return .snooze(reminderID)
        default:
            // An action identifier this app version does not register (e.g. a
            // banner scheduled by an older build) is inert, never guessed at.
            return .none
        }
    }
}
