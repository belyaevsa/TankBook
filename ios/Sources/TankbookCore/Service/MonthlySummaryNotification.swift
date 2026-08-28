import Foundation

// MARK: - P6.2 monthly summary local notification (docs/NOTIFICATIONS.md)

/// The monthly-summary local notification (J8): "August: 212 € on the Volvo.",
/// fired on the 1st of the month at 10:00 local, summarizing the calendar month
/// that just ended. A pure value type so the decision layer tests as data -
/// the same split P3.6 established for `ReminderNotification`
/// (docs/TESTING.md L1). `UNUserNotificationCenter` never sees this type; the
/// app's adapter turns it into a `UNNotificationRequest`.
///
/// Money is the stored snapshot (hard rule 3): `amount` is the SUM of the
/// month's entries' `homeAmount`s, each written when its entry's rate was known
/// - never re-derived at a later rate. `homeCurrency` is the vehicle's own, so
/// each vehicle's figure is self-consistent even across a multi-currency garage.
public struct MonthlySummaryNotification: Equatable, Sendable {
    /// The notification body, carrying runtime data (the summarized month, the
    /// figure, the car) but no localized text - localization lives in the app,
    /// where the String Catalog renders one full phrase per language
    /// (docs/NOTIFICATIONS.md's copy is never concatenated copy).
    public struct Body: Equatable, Sendable {
        /// The summarized calendar month's year (e.g. 2025 for "August").
        public var summaryYear: Int
        /// The summarized calendar month, 1-12 (e.g. 8 for August).
        public var summaryMonth: Int
        /// The month's total spend in `homeCurrency`, summed from the entries'
        /// stored `homeAmount` snapshots - never a re-conversion at today's rate.
        public var amount: Decimal
        public var homeCurrency: CurrencyCode
        /// The car's name, as stored ("Volvo V60").
        public var vehicleName: String

        public init(summaryYear: Int, summaryMonth: Int,
                    amount: Decimal, homeCurrency: CurrencyCode,
                    vehicleName: String) {
            self.summaryYear = summaryYear
            self.summaryMonth = summaryMonth
            self.amount = amount
            self.homeCurrency = homeCurrency
            self.vehicleName = vehicleName
        }
    }

    public var vehicleID: UUID
    /// When it fires: the 1st of the month following the summarized month, at
    /// 10:00 local (docs/NOTIFICATIONS.md -> Quiet by scheduling).
    public var fireDate: Date
    public var body: Body

    public init(vehicleID: UUID, fireDate: Date, body: Body) {
        self.vehicleID = vehicleID
        self.fireDate = fireDate
        self.body = body
    }

    /// The stable identifier under which the notification is scheduled. Encodes
    /// the vehicle AND the summarized month so two sequential summaries coexist
    /// on a boundary day (the about-to-fire August summary on 1 September sits
    /// beside the newly armed September one) while a re-arm of the SAME month -
    /// a later launch with fresher data - replaces by identifier rather than
    /// stacking a duplicate (docs/NOTIFICATIONS.md -> Multi-device behavior).
    public var identifier: String {
        "monthly-summary.\(vehicleID.uuidString).\(body.summaryYear)-"
            + String(format: "%02d", body.summaryMonth)
    }
}

/// What the monthly-summary world should be: the notifications to schedule and
/// the identifiers to remove, as pure data (mirrors `ReminderNotificationPlan`,
/// P3.6). The adapter materializes only the future subset.
public struct MonthlySummaryNotificationPlan: Equatable, Sendable {
    public var scheduled: [MonthlySummaryNotification]
    public var cancelled: Set<String>

    public init(scheduled: [MonthlySummaryNotification], cancelled: Set<String> = []) {
        self.scheduled = scheduled
        self.cancelled = cancelled
    }
}

/// The pure scheduling decision for the monthly summary (docs/NOTIFICATIONS.md,
/// the catalog row "Monthly summary (J8)"):
///
/// 1. **One notification per car that spent that month.** Money is a pair whose
///    `homeCurrency` is the vehicle's own, so a household's cars can carry
///    different currencies and an aggregate would silently mix them
///    (docs/SCHEMA.md: "stats mixing home currencies render per-currency
///    subtotals"). One per car keeps the doc's own format - "August: 212 € on
///    the Volvo." - and matches Trends, which is per-car. DECIDED here and
///    written into docs/NOTIFICATIONS.md.
/// 2. **A month with nothing to say produces NO notification.** No entries at
///    all, entries whose `homeAmount` is still pending a rate (F9), or a zero
///    total - none of these push. A push that tells the user nothing happened
///    is a nag.
/// 3. **The amount is the stored snapshot sum** (hard rule 3): each entry
///    contributes its `homeAmount` written when the rate was known; nothing is
///    re-converted at a later rate.
/// 4. **Re-armed on every reconcile** (launch, foreground, toggle change): the
///    plan names the NEXT first-of-month 10:00 and the month that precedes it,
///    and the stable identifier makes a re-arm a replace, not a stack.
public enum MonthlySummaryPlanner {

    /// The humane hour for the summary (docs/NOTIFICATIONS.md: "1st of month,
    /// 10:00"). Nothing time-critical exists in a fuel log, so nothing fires at
    /// night (Quiet by scheduling).
    public static let fireHour = 10

    // MARK: - Plan

    /// The reconciliation over the garage: what the monthly summary world should
    /// be. `enabled` is `Preferences.notifications.monthlySummary` (default OFF,
    /// docs/SCHEMA.md). With the feature OFF the plan cancels every vehicle's
    /// pending summary identifier - toggling OFF must cancel, not merely stop
    /// scheduling new ones. With it ON, each non-archived vehicle with real
    /// spend in the current month schedules its notification; an archived car
    /// stops summarizing (its reason is gone - docs/NOTIFICATIONS.md ->
    /// Multi-device cleanup).
    public static func plan(vehicles: [Vehicle],
                            entriesByVehicle: [UUID: [any Entry]],
                            duplicateResolutions: Set<DuplicateDetector.PairKey> = [],
                            now: Date,
                            enabled: Bool,
                            calendar: Calendar = .current) -> MonthlySummaryNotificationPlan {
        guard enabled else {
            return MonthlySummaryNotificationPlan(
                scheduled: [],
                cancelled: cancelledIdentifiers(for: vehicles, at: now, calendar: calendar))
        }

        var scheduled: [MonthlySummaryNotification] = []
        var cancelled: Set<String> = []

        for vehicle in vehicles {
            if vehicle.archived {
                cancelled.formUnion(cancelledIdentifiers(for: [vehicle], at: now, calendar: calendar))
                continue
            }
            let entries = entriesByVehicle[vehicle.id] ?? []
            if let notification = summary(for: vehicle, entries: entries,
                                           duplicateResolutions: duplicateResolutions,
                                           now: now, calendar: calendar) {
                scheduled.append(notification)
            }
        }

        return MonthlySummaryNotificationPlan(scheduled: scheduled, cancelled: cancelled)
    }

    // MARK: - One vehicle's summary

    /// The notification for one vehicle's just-ended month, or `nil` when the
    /// month has nothing honest to say (no entries, everything rate-pending, or
    /// a zero total). The fire date is the 1st of the FOLLOWING month at 10:00,
    /// so the month being summarized is always the one that just ended when the
    /// notification fires.
    private static func summary(for vehicle: Vehicle,
                                entries: [any Entry],
                                duplicateResolutions: Set<DuplicateDetector.PairKey>,
                                now: Date,
                                calendar: Calendar) -> MonthlySummaryNotification? {
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let month = calendar.dateInterval(of: .month, for: now),
              let summaryYear = components.year,
              let summaryMonth = components.month else {
            return nil
        }

        // The S2 single-count invariant, exactly as HomeStats applies it: only
        // the counting member of an unresolved duplicate pair feeds the totals,
        // so the summary can never double-count (docs/SYNC.md S2).
        let fills = entries.compactMap { $0 as? FillUp }
        let pairs = DuplicateDetector.pairs(in: fills, resolved: duplicateResolutions)
        let excludedIDs = Set(pairs.map(\.excludedID))

        let inMonth = entries.filter { month.contains($0.date) && !excludedIDs.contains($0.id) }
        guard !inMonth.isEmpty else { return nil }

        let total = inMonth.reduce(Decimal.zero) { partial, entry in
            guard let homeAmount = entry.money?.homeAmount else { return partial }
            return partial + homeAmount
        }
        guard total > 0 else { return nil }

        guard let fireDate = firstOfNextMonth(at: now, calendar: calendar) else { return nil }
        return MonthlySummaryNotification(
            vehicleID: vehicle.id,
            fireDate: fireDate,
            body: MonthlySummaryNotification.Body(
                summaryYear: summaryYear,
                summaryMonth: summaryMonth,
                amount: total,
                homeCurrency: vehicle.homeCurrency,
                vehicleName: vehicle.name))
    }

    // MARK: - Cancellation

    /// Every identifier a vehicle's pending summary can live under right now.
    /// The summary month is the month that was current when the notification was
    /// last armed, so on a boundary day (the 1st) both the previous month's
    /// about-to-fire summary and the current month's newly armed one can be
    /// pending at once; two candidates cover both. A notification older than
    /// the previous month has already fired, so nothing older needs cancelling.
    public static func cancelledIdentifiers(for vehicles: [Vehicle],
                                            at now: Date,
                                            calendar: Calendar = .current) -> Set<String> {
        var identifiers = Set<String>()
        for vehicle in vehicles {
            identifiers.insert(identifier(for: vehicle, at: now, calendar: calendar))
            if let previous = calendar.date(byAdding: .month, value: -1, to: now) {
                identifiers.insert(identifier(for: vehicle, at: previous, calendar: calendar))
            }
        }
        return identifiers
    }

    /// The identifier a vehicle's summary for the month containing `date` lives
    /// under - the same shape `identifier` produces on the notification.
    public static func identifier(for vehicle: Vehicle,
                                  at date: Date,
                                  calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        return "monthly-summary.\(vehicle.id.uuidString).\(year)-"
            + String(format: "%02d", month)
    }

    // MARK: - Materialization

    /// The subset of a plan's scheduled notifications whose fire date is still
    /// ahead - what the adapter actually schedules. A past fire date means the
    /// notification already fired (or the month's summary was superseded);
    /// scheduling it again would re-open a summary the user already saw.
    public static func pending(_ notifications: [MonthlySummaryNotification],
                               at now: Date) -> [MonthlySummaryNotification] {
        notifications.filter { $0.fireDate > now }
    }

    // MARK: - Date helpers

    /// The first of the month AFTER `date`'s month, at `fireHour` local - the
    /// moment the just-ended month is summarized. A December `date` rolls to
    /// January of the next year (Calendar normalizes overflow components).
    private static func firstOfNextMonth(at date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        return calendar.date(from: DateComponents(
            year: year, month: month + 1, day: 1, hour: fireHour))
    }
}
