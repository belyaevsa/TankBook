import Foundation
import Observation
import UserNotifications
import TankbookCore

/// The `UNUserNotificationCenter` adapter (P3.6). Thin by design: it turns the
/// plan's value types into `UNNotificationRequest`s, schedules only the pending
/// (future) subset, cancels by identifier, and maps the platform's authorization
/// status onto `LocalNotificationAuthorization`. Everything that is a decision
/// lives in `ReminderNotificationPlanner` / `NotificationPermissionGate`, which
/// test without this framework - this type only obeys.
struct UNNotificationScheduler: LocalNotificationScheduling {

    func schedule(_ notifications: [ReminderNotification]) async {
        let center = UNUserNotificationCenter.current()
        for notification in ReminderNotificationPlanner.pending(notifications, at: Date()) {
            let content = UNMutableNotificationContent()
            content.body = ReminderNotificationText.body(for: notification.body)
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }

    func cancel(identifiers: [String]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func authorization() async -> LocalNotificationAuthorization {
        Self.ensureDelegate()
        if let forced = ProcessInfo.processInfo.arguments.notificationStatusOverride {
            return forced
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        Self.ensureDelegate()
        if let forced = ProcessInfo.processInfo.arguments.notificationStatusOverride {
            return forced
        }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    private static func map(_ status: UNAuthorizationStatus) -> LocalNotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }

    /// Keeps the foreground-presentation delegate alive and installed once, so a
    /// reminder firing at 09:00/10:00 while the app is open still shows its
    /// banner rather than silently vanishing.
    private static let delegate = NotificationDelegate()

    private static func ensureDelegate() {
        UNUserNotificationCenter.current().delegate = delegate
    }
}

/// Presents user-visible notifications while the app is foregrounded (the
/// default would suppress them, which would make a humane-hour reminder that
/// fires during use disappear). No tap handling: tapping opens the app to its
/// current state; the reminder deep link to the Reminders screen is out of
/// P3.6's scope.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// The DEBUG/test-only `-notificationStatus <value>` override, mirroring the
/// camera's `-cameraStatus` hook: forces the authorization state so the denied
/// card and its UI-test assertions are reachable deterministically on a
/// simulator without touching the real permission dialog.
private extension Array where Element == String {
    var notificationStatusOverride: LocalNotificationAuthorization? {
        guard let index = firstIndex(of: "-notificationStatus"), index + 1 < count else { return nil }
        switch self[index + 1] {
        case "authorized": return .authorized
        case "denied": return .denied
        case "notDetermined": return .notDetermined
        default: return nil
        }
    }
}

/// Renders a plan body through the String Catalog (docs/NOTIFICATIONS.md copy:
/// a full localised phrase per language, never concatenation - the count-bearing
/// sub-phrase carries real plural rules).
enum ReminderNotificationText {
    static func body(for body: ReminderNotification.Body) -> String {
        switch body {
        case .dateDue(let title, let days):
            String(format: L10n.localize("%1$@ in %2$@"), title, daysPhrase(days))
        case .odometerDue(let title, let km):
            String(format: L10n.localize("%1$@ within %2$@"), title, kmPhrase(km))
        case .overdue(let title):
            String(format: L10n.localize("Still pending: %1$@"), title)
        }
    }

    private static func daysPhrase(_ days: Int) -> String {
        String(localized: "\(days) days")
    }

    private static func kmPhrase(_ km: Int) -> String {
        String(format: L10n.localize("%lld km"), km)
    }
}

/// Owns the notification reconciliation and the permission state (P3.6). The
/// single place reminders are turned into pending local notifications: it
/// computes the plan, persists the stored `.attention` transition (so an
/// odometer crossing arms exactly once), and applies the plan to the injected
/// scheduler. The permission request is fired at the first reminder creation -
/// never at launch - and a denial surfaces as a one-time card, never a nag.
@MainActor
@Observable
final class ReminderNotificationCoordinator {
    private let scheduling: any LocalNotificationScheduling

    private(set) var authorization: LocalNotificationAuthorization = .notDetermined
    private var didRequestThisLaunch = false
    private var deniedCardHandled: Bool

    init(scheduling: any LocalNotificationScheduling = UNNotificationScheduler(),
         userDefaults: UserDefaults = .standard) {
        self.scheduling = scheduling
        self.deniedCardHandled = userDefaults.bool(forKey: Self.deniedCardHandledKey)
    }

    private static let deniedCardHandledKey = "notifications.deniedCardHandled"

    /// Whether the one-time denied card should show (docs/ERRORS.md -> Reminders).
    var showsDeniedCard: Bool {
        NotificationPermissionGate.shouldShowDeniedCard(
            authorization: authorization,
            hasActiveReminders: hasActiveReminders,
            cardAlreadyHandled: deniedCardHandled)
    }

    // MARK: - Reconciliation

    /// Recomputes the plan and applies it, persisting the stored `.attention`
    /// transition first so a `.scheduled -> .attention` crossing arms once. The
    /// plan is computed from the PRE-transition statuses for exactly that
    /// reason. Returns the reminders with their updated statuses for rendering.
    @discardableResult
    func reconcile(vehicleId: UUID) async -> [Reminder] {
        guard let repository = try? AppStore.repository() else { return [] }
        await refreshAuthorization()

        let live = (try? repository.liveReminders(forVehicle: vehicleId)) ?? []
        let now = Date()
        let vehicle = try? repository.vehicle(id: vehicleId)
        let entries = (try? repository.liveEntries(forVehicle: vehicleId)) ?? []
        let odometer = entries.compactMap(\.odometer).max() ?? vehicle?.initialOdometer

        hasActiveReminders = live.contains { ReminderLifecycle.isActive($0) }

        let plan = ReminderNotificationPlanner.plan(
            reminders: live, now: now, currentOdometer: odometer)

        var updated: [Reminder] = []
        for reminder in live where ReminderLifecycle.isActive(reminder) {
            let derived = ReminderLifecycle.derivedStatus(
                reminder, currentOdometer: odometer, now: now)
            if derived != reminder.status {
                var next = reminder
                next.status = derived
                try? repository.upsertReminder(next)
                updated.append(next)
            } else {
                updated.append(reminder)
            }
        }

        await apply(plan)
        return updated
    }

    /// Cancels a deleted reminder's pending notifications everywhere. Deletion
    /// tombstones the row out of `liveReminders`, so the plan cannot see it -
    /// the delete site calls this with the reminder it just removed.
    func cancelNotifications(for reminder: Reminder) async {
        await scheduling.cancel(identifiers: ReminderNotificationPlanner.identifiers(for: reminder))
    }

    /// The permission request at the first reminder creation (never at launch,
    /// never a repeat after a denial - docs/NOTIFICATIONS.md).
    func requestPermissionIfFirstReminder(vehicleId: UUID) async {
        await refreshAuthorization()
        let hasActive = await activeRemindersExist(vehicleId: vehicleId)
        hasActiveReminders = hasActive
        guard NotificationPermissionGate.shouldRequest(
            authorization: authorization,
            hasActiveReminders: hasActive,
            didRequestThisLaunch: didRequestThisLaunch) else { return }
        didRequestThisLaunch = true
        authorization = await scheduling.requestAuthorization()
        // A fresh denial flips the card into view once; a grant means no card.
        if authorization == .denied {
            deniedCardHandled = false
            UserDefaults.standard.set(false, forKey: Self.deniedCardHandledKey)
        }
    }

    /// Dismisses the denied card ("fine as is") - it never returns.
    func dismissDeniedCard() {
        deniedCardHandled = true
        UserDefaults.standard.set(true, forKey: Self.deniedCardHandledKey)
    }

    func refreshAuthorization() async {
        authorization = await scheduling.authorization()
    }

    // MARK: - Internals

    /// Whether the coordinator currently believes active reminders exist. Kept
    /// as the last-seen value from a reconcile so the card can be derived without
    /// an async read; updated on every reconcile/creation.
    private var hasActiveReminders = false

    private func activeRemindersExist(vehicleId: UUID) async -> Bool {
        guard let repository = try? AppStore.repository() else { return false }
        let live = (try? repository.liveReminders(forVehicle: vehicleId)) ?? []
        return live.contains { ReminderLifecycle.isActive($0) }
    }

    private func apply(_ plan: ReminderNotificationPlan) async {
        await scheduling.schedule(plan.scheduled)
        await scheduling.cancel(identifiers: Array(plan.cancelled))
    }
}
