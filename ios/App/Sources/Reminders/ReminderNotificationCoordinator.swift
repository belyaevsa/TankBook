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

    func scheduleMonthlySummary(_ notifications: [MonthlySummaryNotification]) async {
        let center = UNUserNotificationCenter.current()
        for notification in MonthlySummaryPlanner.pending(notifications, at: Date()) {
            let content = UNMutableNotificationContent()
            content.body = MonthlySummaryNotificationText.body(for: notification)
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

    func cancelMonthlySummary(identifiers: [String]) async {
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

    /// Wires a tapped notification to the app's navigation (PJ.5,
    /// docs/NOTIFICATIONS.md). Called once at launch by the root view, which
    /// owns the router the closure captures; the delegate resolves the tapped
    /// identifier through the core mapping and forwards the route here.
    @MainActor
    static func configureOpenHandler(_ handler: @escaping @MainActor (NotificationRoute) -> Void) {
        ensureDelegate()
        delegate.onOpen = handler
    }

    /// Keeps the foreground-presentation delegate alive and installed once, so a
    /// reminder firing at 09:00/10:00 while the app is open still shows its
    /// banner rather than silently vanishing.
    private static let delegate = NotificationDelegate()

    /// `fileprivate` (not `private`): `ReminderNotificationCoordinator.init`
    /// installs the delegate too, so a cold-start tap is not dropped.
    fileprivate static func ensureDelegate() {
        UNUserNotificationCenter.current().delegate = delegate
    }
}

/// Presents user-visible notifications while the app is foregrounded (the
/// default would suppress them, which would make a humane-hour reminder that
/// fires during use disappear), and routes a TAP to the screen it promised
/// (PJ.5, docs/SCREENMAP.md -> the deep link). Both methods are thin: they
/// translate a platform object into a decision, and every decision - the
/// identifier -> route mapping, the destination - lives in core /
/// `NotificationRouter`, which test without this framework.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Where a tapped notification should drive the app (PJ.5), set by
    /// `AppRootView` at launch. A closure rather than a method on the delegate
    /// because the navigation state lives in SwiftUI; the router it captures is
    /// a reference type held by the view, so a background-thread tap can reach
    /// MainActor state through a hop.
    @MainActor var onOpen: ((NotificationRoute) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// The tap: resolve the tapped identifier to a route and hand it to the
    /// app's navigation router. Unknown or malformed identifiers resolve to
    /// `.none`, which routes nowhere - the app just opens (hard rule 7: a stale
    /// notification - a reminder deleted since it was scheduled - must never
    /// dead-end, and never route somewhere arbitrary). Called off the main
    /// thread, so the router is reached through a MainActor hop.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = NotificationRouteParser.resolve(
            identifier: response.notification.request.identifier)
        completionHandler()
        Task { @MainActor in
            self.onOpen?(route)
        }
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

/// Renders a monthly-summary notification body (P6.2, docs/NOTIFICATIONS.md:
/// "August: 212 € on the Volvo."). One full localised phrase per language,
/// never concatenation - the month name, the amount and the car name are three
/// slots of a single catalogue key (the P1.4 lesson: "%@ spend" composed as
/// "%@ расходы" rendered word-order nonsense in Russian). The amount follows
/// the app's money convention - "212 €" with the symbol after, no-break spaced -
/// through the same `HomeFormat.spend` every other figure uses, so the
/// notification and the Trends tile can never disagree about a number.
enum MonthlySummaryNotificationText {
    static func body(for notification: MonthlySummaryNotification) -> String {
        let month = monthName(year: notification.body.summaryYear,
                              month: notification.body.summaryMonth)
        let amount = HomeFormat.spend(notification.body.amount,
                                      symbol: AddVehicleSupport.currencySymbol(
                                          for: notification.body.homeCurrency))
        return String(format: L10n.localize("%1$@: %2$@ on the %3$@"),
                      month, amount, notification.body.vehicleName)
    }

    /// "August" - the summarized month's name in the current locale
    /// (nominative: the name never declines in either supported language).
    private static func monthName(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMM",
                                                        options: 0,
                                                        locale: Locale.current)
        guard let date = Calendar.current.date(from: components) else { return "" }
        return formatter.string(from: date)
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
        // PJ.5: the tap delegate is installed as soon as the coordinator (and
        // with it the app) exists, so a tap that COLD-STARTS the app - the
        // response arrives right after launch - still routes instead of being
        // dropped for a delegate that was never set.
        UNNotificationScheduler.ensureDelegate()
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

    // MARK: - Monthly summary (P6.2, docs/NOTIFICATIONS.md)

    /// Recomputes and applies the monthly-summary plan over the whole garage.
    /// Runs at launch/foreground and on every toggle change, so the armed
    /// notification is always the NEXT first-of-month 10:00 with the freshest
    /// data the device has - a re-arm replaces by identifier, never stacks. With
    /// the preference OFF this is also the cancellation path: the plan cancels
    /// every vehicle's pending identifier, which is what makes "turning the
    /// toggle OFF cancels the pending request" provable (mutation 2).
    func reconcileMonthlySummary() async {
        guard let repository = try? AppStore.repository() else { return }
        let vehicles = (try? repository.liveVehicles()) ?? []
        var entriesByVehicle: [UUID: [any Entry]] = [:]
        for vehicle in vehicles {
            entriesByVehicle[vehicle.id] = (try? repository.liveEntries(forVehicle: vehicle.id)) ?? []
        }
        let resolutions = (try? repository.resolvedDuplicateKeys()) ?? []
        let enabled = (try? repository.livePreferences())?.notifications.monthlySummary ?? false
        let plan = MonthlySummaryPlanner.plan(
            vehicles: vehicles,
            entriesByVehicle: entriesByVehicle,
            duplicateResolutions: resolutions,
            now: Date(),
            enabled: enabled)
        await applyMonthly(plan)
    }

    /// The opt-in toggle (Trends, `notifications.monthlySummary`, default OFF).
    /// Persists the preference, then - only when turning ON - requests system
    /// permission at this, the summary's first moment of need (never at launch,
    /// never a repeat once decided - docs/NOTIFICATIONS.md). Turning OFF skips
    /// the permission path and goes straight to the reconcile, which cancels.
    func setMonthlySummaryEnabled(_ enabled: Bool) async {
        guard let repository = try? AppStore.repository() else { return }
        var preferences = (try? repository.livePreferences())
            ?? Preferences(createdAt: Date(), updatedAt: Date())
        preferences.notifications.monthlySummary = enabled
        preferences.updatedAt = Date()
        try? repository.upsertPreferences(preferences)

        if enabled {
            await refreshAuthorization()
            if NotificationPermissionGate.shouldRequestForMonthlySummary(
                authorization: authorization, didRequestThisLaunch: didRequestThisLaunch) {
                didRequestThisLaunch = true
                authorization = await scheduling.requestAuthorization()
            }
        }
        await reconcileMonthlySummary()
    }

    /// Cancels a vehicle's pending monthly-summary notifications. Called from
    /// the archive and delete sites (J13): a car that is no longer active has
    /// no summary reason, and its notification must not linger. The identifier
    /// carries the vehicle id, so the plan - which only sees live vehicles -
    /// cannot reach a deleted row; the site that removed it can.
    func cancelMonthlySummary(forVehicle vehicleID: UUID) async {
        guard let repository = try? AppStore.repository(),
              let vehicle = try? repository.vehicle(id: vehicleID) else { return }
        let identifiers = MonthlySummaryPlanner.cancelledIdentifiers(for: [vehicle], at: Date())
        await scheduling.cancelMonthlySummary(identifiers: Array(identifiers))
    }

    private func applyMonthly(_ plan: MonthlySummaryNotificationPlan) async {
        await scheduling.scheduleMonthlySummary(plan.scheduled)
        await scheduling.cancelMonthlySummary(identifiers: Array(plan.cancelled))
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
