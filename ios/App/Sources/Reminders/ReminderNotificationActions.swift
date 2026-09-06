import Foundation
import UserNotifications
import TankbookCore

/// The fired-reminder notification category (RV.78, docs/NOTIFICATIONS.md ->
/// the actions, design/screens/ReminderNotification.dc.html). One category with
/// two actions, registered once at launch and attached to every reminder
/// notification's request, so a fired banner can be acted on without opening
/// the app:
///
/// - **Mark done** carries `.foreground`: it opens the app on the completion
///   sheet (the cost log stays the user's choice - J7c), never a silent
///   `.done(nil)`.
/// - **Push a week** carries no options: it is handled in the background and
///   needs no screen.
///
/// The action identifiers and the category identifier are the core-owned
/// `ReminderBannerAction` constants so the registered category, the scheduled
/// request and the response parser cannot drift; only the user-facing titles
/// (full localised phrases per language, hard rule 10) live here.
enum ReminderNotificationActions {
    static func category() -> UNNotificationCategory {
        let markDone = UNNotificationAction(
            identifier: ReminderBannerAction.complete.rawValue,
            title: String(localized: "Mark done"),
            options: [.foreground])
        let pushAWeek = UNNotificationAction(
            identifier: ReminderBannerAction.snooze.rawValue,
            title: String(localized: "Push a week"),
            options: [])
        return UNNotificationCategory(
            identifier: ReminderBannerAction.categoryIdentifier,
            actions: [markDone, pushAWeek],
            intentIdentifiers: [],
            options: [])
    }
}

#if DEBUG
/// The `-demoReminderBanner <delaySecs>` launch hook (RV.78 screenshots):
/// requests notification permission and schedules a REAL category-attached
/// banner from the artboard's fired-oil-change state, so the simulator presents
/// it from its own notification system (a banner cannot be staged any other
/// way). The permission request on a fresh install shows the system dialog
/// once; screenshots therefore run after a one-time grant. Compiled out of
/// release builds: this cannot ship.
enum ReminderBannerDemo {
    nonisolated(unsafe) private static var didSchedule = false

    /// Nonisolated because the delegate's `ensureDelegate` runs from a
    /// nonisolated scheduler context; the work hops to the main actor.
    nonisolated static func scheduleIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !didSchedule,
              let index = arguments.firstIndex(of: "-demoReminderBanner"),
              arguments.indices.contains(index + 1),
              let delay = Double(arguments[index + 1]) else { return }
        didSchedule = true
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            let content = UNMutableNotificationContent()
            // The same shape a real fired reminder schedules: body only, via
            // the real composer, so the banner is the app's own presentation.
            let title = Locale.current.language.languageCode?.identifier == "ru"
                ? "Замена масла"
                : "Oil change"
            content.body = ReminderNotificationText.body(for: .overdue(title: title))
            content.categoryIdentifier = ReminderBannerAction.categoryIdentifier
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "RV.78.demo",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
            try? await center.add(request)
        }
    }
}
#endif
