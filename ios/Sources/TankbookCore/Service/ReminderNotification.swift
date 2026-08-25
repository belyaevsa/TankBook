import Foundation

// MARK: - P3.6 local notifications (docs/NOTIFICATIONS.md, docs/ERRORS.md)

/// The local-notification authorization state, as a platform-neutral enum so
/// the permission decisions test in the package without `UNUserNotificationCenter`
/// (the app's adapter maps `UNAuthorizationStatus` onto it). The three states
/// are the only ones the permission rules distinguish.
public enum LocalNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// One local notification the planner wants pending. A pure value type so the
/// entire decision layer - which reminders notify, when, with what body - tests
/// as data (docs/TESTING.md L1), the same split as `ServiceEntryDraft`,
/// `PumpPhotoGate` and `TireMileage`. `UNUserNotificationCenter` never sees this
/// type; the app's adapter turns it into a `UNNotificationRequest`.
public struct ReminderNotification: Equatable, Sendable {
    /// The reason the notification exists. Each reminder can own at most one of
    /// each kind, so the identifier is `reminder.<id>.<kind>` and scheduling a
    /// new one for the same kind replaces the old by identifier.
    public enum Kind: String, Sendable, CaseIterable {
        case date
        case odometer
        case overdue
    }

    /// The body, carrying runtime data (the reminder title, the count) but no
    /// localized text - localization lives in the app, where the String Catalog
    /// and its plural rules are (docs/NOTIFICATIONS.md's copy is a full
    /// localised phrase per language, never concatenation).
    public enum Body: Equatable, Sendable {
        /// "… in 12 days" - the due-window-start line for a date reminder.
        case dateDue(title: String, days: Int)
        /// "… within 500 km" - armed at write time when an odometer reminder
        /// crosses its km window.
        case odometerDue(title: String, km: Int)
        /// "Still pending: …" - the single overdue follow-up.
        case overdue(title: String)
    }

    public var reminderId: UUID
    public var kind: Kind
    public var fireDate: Date
    public var body: Body

    public init(reminderId: UUID, kind: Kind, fireDate: Date, body: Body) {
        self.reminderId = reminderId
        self.kind = kind
        self.fireDate = fireDate
        self.body = body
    }

    /// The stable identifier under which the notification is scheduled. Stable
    /// across reschedules so a re-arm replaces, and known ahead of time so a
    /// resolution (complete/dismiss/reschedule/delete) can cancel it everywhere
    /// without remembering the exact fire date it was armed with.
    public var identifier: String {
        "reminder.\(reminderId.uuidString).\(kind.rawValue)"
    }
}

/// What the planner wants the pending-notification world to be: the
/// notifications to have scheduled, and the identifiers to remove.
///
/// The plan declares INTENT, including entries whose fire date is already in
/// the past (the single overdue follow-up stays listed while the reminder is
/// overdue, so "exactly one, never a nag loop" holds as a count regardless of
/// how far past due `now` is). The adapter materializes only the future subset
/// (`ReminderNotificationPlanner.pending`); a past fire date means the
/// notification already fired and must not be re-scheduled.
public struct ReminderNotificationPlan: Equatable, Sendable {
    public var scheduled: [ReminderNotification]
    public var cancelled: Set<String>

    public init(scheduled: [ReminderNotification], cancelled: Set<String> = []) {
        self.scheduled = scheduled
        self.cancelled = cancelled
    }
}

/// The pure scheduling decision layer (docs/NOTIFICATIONS.md, the three rows of
/// the scenario catalog that are local notifications):
///
/// 1. **Date reminder** - "morning of the due-window start (09:00 local)": the
///    notification fires at 09:00 on `dueDate - attentionWindowDays`. Deterministic
///    from the due date, so it is listed whenever a reminder has one.
/// 2. **Odometer reminder** - "local, armed at write time": fires the day after
///    the save that crossed the threshold, at 10:00. Because km cannot fire in
///    the background, it is armed when a still-`.scheduled` reminder first comes
///    inside its km window; a stored `.attention` has already armed and is NOT
///    re-armed (fire once - docs/SCHEMA.md's stored transition).
/// 3. **Overdue follow-up** - "exactly one, 7 days after due, never a nag
///    loop": fires at 09:00 on `dueDate + 7 days`, listed while the reminder is
///    overdue and never more than once per reminder.
///
/// Everything user-visible fires at a humane fixed time (09:00/10:00 local);
/// nothing is ever scheduled at the due moment itself, so nothing buzzes at
/// night (docs/NOTIFICATIONS.md -> Quiet by scheduling).
public enum ReminderNotificationPlanner {

    /// The humane hour for date reminders and the overdue follow-up.
    public static let dateHour = 9

    /// The humane hour for odometer reminders (the "evening after the save",
    /// rounded up to the next humane slot).
    public static let odometerHour = 10

    /// The overdue follow-up lands this many days after the due date.
    public static let overdueFollowUpDays = 7

    // MARK: - Plan

    /// The reconciliation over the current reminders (active AND terminal rows):
    /// what should be scheduled and what should be cancelled. Terminal rows
    /// cancel everything they owned; an active row cancels only the identifiers
    /// whose reason no longer exists (a reschedule that removed a field). A
    /// deleted reminder is absent from `reminders` - its cancellation goes
    /// through `identifiers(for:)` at the delete site.
    public static func plan(reminders: [Reminder],
                            now: Date,
                            currentOdometer: Int?,
                            calendar: Calendar = .current) -> ReminderNotificationPlan {
        var scheduled: [ReminderNotification] = []
        var cancelled: Set<String> = []

        for reminder in reminders {
            if ReminderLifecycle.isActive(reminder) {
                scheduled.append(contentsOf: schedule(for: reminder,
                                                      now: now,
                                                      currentOdometer: currentOdometer,
                                                      calendar: calendar))
                if reminder.dueDate == nil {
                    cancelled.insert(identifier(.date, for: reminder))
                    cancelled.insert(identifier(.overdue, for: reminder))
                }
                if reminder.dueOdometer == nil {
                    cancelled.insert(identifier(.odometer, for: reminder))
                }
            } else {
                cancelled.formUnion(identifiers(for: reminder))
            }
        }

        return ReminderNotificationPlan(scheduled: scheduled, cancelled: cancelled)
    }

    /// The notifications an active reminder warrants, independent of what was
    /// scheduled before. Date and overdue entries are deterministic from the due
    /// date; the odometer entry is gated on the stored `.scheduled` status so it
    /// arms once rather than on every recompute.
    private static func schedule(for reminder: Reminder,
                                 now: Date,
                                 currentOdometer: Int?,
                                 calendar: Calendar) -> [ReminderNotification] {
        var result: [ReminderNotification] = []

        if let dueDate = reminder.dueDate {
            let fire = at(hour: dateHour,
                          on: calendar.date(byAdding: .day,
                                            value: -ReminderLifecycle.attentionWindowDays,
                                            to: calendar.startOfDay(for: dueDate)) ?? dueDate,
                          calendar: calendar)
            result.append(ReminderNotification(
                reminderId: reminder.id, kind: .date, fireDate: fire,
                body: .dateDue(title: reminder.title,
                               days: ReminderLifecycle.attentionWindowDays)))
        }

        if let dueOdometer = reminder.dueOdometer,
           reminder.status == .scheduled,
           let km = ReminderLifecycle.kmRemaining(until: dueOdometer, from: currentOdometer),
           km <= ReminderLifecycle.attentionWindowKm {
            let fire = at(hour: odometerHour,
                          on: calendar.date(byAdding: .day,
                                            value: 1,
                                            to: calendar.startOfDay(for: now)) ?? now,
                          calendar: calendar)
            result.append(ReminderNotification(
                reminderId: reminder.id, kind: .odometer, fireDate: fire,
                body: .odometerDue(title: reminder.title,
                                   km: ReminderLifecycle.attentionWindowKm)))
        }

        if let dueDate = reminder.dueDate,
           ReminderLifecycle.daysRemaining(until: dueDate, from: now) < 0 {
            let fire = at(hour: dateHour,
                          on: calendar.date(byAdding: .day,
                                            value: overdueFollowUpDays,
                                            to: calendar.startOfDay(for: dueDate)) ?? dueDate,
                          calendar: calendar)
            result.append(ReminderNotification(
                reminderId: reminder.id, kind: .overdue, fireDate: fire,
                body: .overdue(title: reminder.title)))
        }

        return result
    }

    // MARK: - Identifiers

    /// Every identifier a reminder's notifications can live under. Used by the
    /// four resolution paths (complete / reschedule / dismiss / delete) to
    /// cancel the reminder's pending notifications everywhere, whatever kind it
    /// had armed (docs/NOTIFICATIONS.md -> Multi-device behavior).
    public static func identifiers(for reminder: Reminder) -> [String] {
        ReminderNotification.Kind.allCases.map { identifier($0, for: reminder) }
    }

    /// The stable identifier for one reminder + kind.
    public static func identifier(_ kind: ReminderNotification.Kind,
                                  for reminder: Reminder) -> String {
        "reminder.\(reminder.id.uuidString).\(kind.rawValue)"
    }

    // MARK: - Materialization

    /// The subset of a plan's scheduled notifications whose fire date is still
    /// ahead - what the adapter actually schedules. A past fire date means the
    /// notification already fired; scheduling it again would re-open the nag
    /// loop the overdue rule exists to forbid.
    public static func pending(_ notifications: [ReminderNotification],
                               at now: Date) -> [ReminderNotification] {
        notifications.filter { $0.fireDate > now }
    }

    // MARK: - Date helpers

    private static func at(hour: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}

// MARK: - Permission policy (docs/NOTIFICATIONS.md -> Permission & quiet behavior)

/// The permission decisions as pure functions over the authorization state, so
/// "requested at the first reminder creation, never at launch" and "denied shows
/// the one-time card, never a nag" test without a permission dialog. The app
/// calls these from the reminder-creation flow and the Reminders screen; the
/// policy itself holds no state.
public enum NotificationPermissionGate {

    /// Whether to request system permission at this moment. Requested only when
    /// the state is still undetermined AND a reminder actually exists AND this
    /// launch has not already asked - never at onboarding, never a repeat
    /// request once denied (a denied state is only ever answered from Settings).
    public static func shouldRequest(authorization: LocalNotificationAuthorization,
                                     hasActiveReminders: Bool,
                                     didRequestThisLaunch: Bool) -> Bool {
        authorization == .notDetermined && hasActiveReminders && !didRequestThisLaunch
    }

    /// Whether to show the one-time denied card (docs/ERRORS.md -> Reminders:
    /// "Reminders can't notify you - they'll only show here."). Shown once, when
    /// permission is denied and reminders exist and the user has not already
    /// dismissed it - never again, no nag loop.
    public static func shouldShowDeniedCard(authorization: LocalNotificationAuthorization,
                                            hasActiveReminders: Bool,
                                            cardAlreadyHandled: Bool) -> Bool {
        authorization == .denied && hasActiveReminders && !cardAlreadyHandled
    }
}

// MARK: - Scheduling seam

/// The thin seam the app's `UNUserNotificationCenter` adapter conforms to. It
/// exists so the coordinator (which holds the plan and applies it) can be handed
/// a recording double in a test, and so the plan logic never touches a platform
/// framework (docs/TESTING.md -> L1). The adapter stays dumb: schedule the
/// pending subset, cancel the identifiers, and report/request authorization.
public protocol LocalNotificationScheduling: Sendable {
    func schedule(_ notifications: [ReminderNotification]) async
    func cancel(identifiers: [String]) async
    func authorization() async -> LocalNotificationAuthorization
    func requestAuthorization() async -> LocalNotificationAuthorization
}
