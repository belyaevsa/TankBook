import Foundation

// MARK: - PJ.5 the notification tap deep link (docs/NOTIFICATIONS.md, docs/SCREENMAP.md)

/// Where a tapped notification should take the app, as a pure value so the
/// identifier -> destination mapping tests as data (docs/TESTING.md L1) - the
/// same split P3.6 established for the planning layer. `UNUserNotificationCenter`
/// never sees this type: the app's delegate resolves an identifier through it,
/// and the app's navigation layer drives the destination.
///
/// Two families are routable today (the identifiers are stable and parseable -
/// `ReminderNotification.identifier` and `MonthlySummaryNotification.identifier`):
///
/// 1. **`reminder.<uuid>.<kind>`** -> the Reminders screen with that reminder's
///    completion flow. The kind (`date` / `odometer` / `overdue`) is part of the
///    identifier format but never the destination: every reminder notification
///    lands on the same screen, for the same reminder.
/// 2. **`monthly-summary.<uuid>.<year>-<month>`** -> the Trends screen.
///
/// Everything else - an unknown identifier, or a malformed one (no dots, a bad
/// UUID, a kind the app does not produce) - is `.none`: the app opens normally.
/// A notification is attacker-adjacent input in the sense that it can be STALE
/// (a reminder deleted since it was scheduled), so a tap must never dead-end
/// (hard rule 7) and never route somewhere arbitrary.
public enum NotificationRoute: Equatable, Sendable {
    /// A reminder notification: land on Reminders with this reminder's
    /// completion flow surfaced.
    case reminder(UUID)
    /// A monthly-summary notification: land on the Trends tab.
    case trends
    /// Unknown or malformed identifier: open the app normally, route nowhere.
    case none
}

/// The pure identifier -> destination mapping (docs/NOTIFICATIONS.md -> "Tap
/// lands on"). Deliberately a function over the identifier string, not a
/// `Decodable`: a notification identifier is a stable app-owned token, never
/// server input, so it is parsed strictly - an identifier the app itself cannot
/// produce is treated as unknown, never guessed at.
public enum NotificationRouteParser {
    public static func resolve(identifier: String) -> NotificationRoute {
        let parts = identifier.split(separator: ".").map(String.init)

        // `monthly-summary.*` routes to Trends. The identifier is
        // `monthly-summary.<vehicleID>.<year>-<month>`; the vehicle and the
        // summarized month are payload, never the destination - Trends is
        // per-car and the selected car is what renders.
        if parts.first == "monthly-summary", parts.count >= 2, !parts[1].isEmpty {
            return .trends
        }

        // `reminder.<uuid>.<kind>` routes to Reminders for that reminder. The
        // kind is validated against the enum so an identifier this app version
        // cannot have produced is malformed, not guessed at.
        guard parts.count == 3,
              parts[0] == "reminder",
              let reminderID = UUID(uuidString: parts[1]),
              ReminderNotification.Kind(rawValue: parts[2]) != nil else {
            return .none
        }
        return .reminder(reminderID)
    }
}
