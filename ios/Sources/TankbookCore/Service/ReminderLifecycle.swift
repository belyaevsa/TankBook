import Foundation

/// The reminder state machine (docs/SCHEMA.md -> "Reminder lifecycle
/// (normative)", docs/JOURNEYS.md J7c). Every transition the lifecycle block
/// names lives here as a pure function over a `Reminder`, so the L1 transition
/// table tests without a simulator and P3.5 (the completion sheet) drives the
/// same code the list screen drives.
///
/// Three rules shape this type:
/// 1. **Complete** takes the reminder to `.done(entryId)` - declining the cost
///    prompt is `.done(nil)`, completion never forces bookkeeping - and, when
///    recurrence is set, creates the NEXT occurrence as a new `Reminder` row
///    anchored at the COMPLETION date/odometer (never the original due - no
///    drift), linked via `sourceEntryId`. Old rows stay as history.
/// 2. **Reschedule** edits dueDate/dueOdometer in place and resets a fired
///    `.attention` to `.scheduled` so it can notify again.
/// 3. **`.attention` is derived at read time from thresholds, but the
///    transition is stored** so P3.6's notifications fire once rather than on
///    every recompute. `derivedStatus` is the read-time derivation; the caller
///    persists a `.scheduled <-> .attention` change when it occurs. Terminal
///    rows (`.done`/`.dismissed`) never re-derive - no re-firing of past
///    events (docs/SCHEMA.md -> Recalculation on edit).
///
/// Delete is deliberately NOT here: it is the repository's tombstone
/// (`softDeleteReminder`) and is distinct from `.dismissed`, which keeps the
/// row with a reason.
public enum ReminderLifecycle {

    // MARK: - Construction seam

    /// The construction seam for a `Reminder` from outside the package (the
    /// synthesized memberwise init is internal on a public struct - the same
    /// blocker that gave `ServiceItem.make` and `Vehicle`'s public init).
    /// Used by the UI-test seed and any future screen that builds a reminder
    /// row without going through `ReminderDraft`. The entity's shape is
    /// unchanged.
    public static func makeReminder(vehicleId: UUID, title: String,
                                    category: ReminderCategory,
                                    dueDate: Date?, dueOdometer: Int?,
                                    recurrence: Reminder.Recurrence? = nil,
                                    sourceEntryId: UUID? = nil,
                                    status: ReminderStatus = .scheduled,
                                    createdAt: Date = Date()) -> Reminder {
        Reminder(id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt, deletedAt: nil,
                 vehicleId: vehicleId, title: title, category: category,
                 dueDate: dueDate, dueOdometer: dueOdometer,
                 recurrence: recurrence, sourceEntryId: sourceEntryId,
                 status: status)
    }

    /// Date-based attention window: a reminder due within this many days (or
    /// already overdue) demands attention. The artboard's "Needs attention"
    /// row is "in 12 days" and NOTIFICATIONS.md arms at "renews in 12 days".
    public static let attentionWindowDays = 12

    /// Odometer-based attention window (docs/NOTIFICATIONS.md: "within 500 km
    /// of the oil change").
    public static let attentionWindowKm = 500

    /// A reminder's due moment, resolved from whichever of date/odometer comes
    /// first (docs/SCHEMA.md -> Reminder: "both = whichever-first"). `nil` for
    /// a row with neither due field - such a row is not a reminder and cannot
    /// be saved (ReminderDraft).
    public enum Due: Equatable, Sendable {
        case date(Date)
        case odometer(Int)
        case both(date: Date, odometer: Int)

        /// A comparable "how due is it" measure for sorting, computed against
        /// the current odometer. The earlier of the two fields wins, exactly as
        /// attention does.
        public func dueSortKey(currentOdometer: Int?, now: Date) -> Int {
            switch self {
            case .date(let date):
                return ReminderLifecycle.daysRemaining(until: date, from: now)
            case .odometer(let odometer):
                guard let currentOdometer else { return .max }
                return odometer - currentOdometer
            case .both(let date, let odometer):
                let days = ReminderLifecycle.daysRemaining(until: date, from: now)
                if let currentOdometer {
                    return min(days, odometer - currentOdometer)
                }
                return days
            }
        }
    }

    /// The result of a complete transition: the completed reminder (now
    /// `.done(entryId)` history) and, when recurrence is set and at least one
    /// anchor is computable, the next occurrence row anchored at completion.
    public struct CompleteResult: Equatable, Sendable {
        public var completed: Reminder
        public var nextOccurrence: Reminder?

        public init(completed: Reminder, nextOccurrence: Reminder?) {
            self.completed = completed
            self.nextOccurrence = nextOccurrence
        }
    }

    // MARK: - Due resolution

    public static func due(_ reminder: Reminder) -> Due? {
        switch (reminder.dueDate, reminder.dueOdometer) {
        case (let date?, nil): return .date(date)
        case (nil, let odometer?): return .odometer(odometer)
        case (let date?, let odometer?): return .both(date: date, odometer: odometer)
        case (nil, nil): return nil
        }
    }

    /// Whole days from `now` to `due`, anchored at the start of each day so
    /// time-of-day never shifts the count. Negative when overdue. This is THE
    /// number the due line and the trailing chip render ("in 12 days"), and the
    /// number the attention derivation tests against.
    public static func daysRemaining(until due: Date, from now: Date) -> Int {
        let calendar = Calendar.current
        let startOf = { calendar.startOfDay(for: $0) }
        return calendar.dateComponents([.day], from: startOf(now), to: startOf(due)).day ?? 0
    }

    /// Kilometres from `current` to `due`, nil when the current odometer is
    /// unknown (the km part cannot be evaluated then). Negative when overdue.
    public static func kmRemaining(until due: Int, from current: Int?) -> Int? {
        guard let current else { return nil }
        return due - current
    }

    // MARK: - Read-time derivation (the stored .attention transition)

    public static func isActive(_ reminder: Reminder) -> Bool {
        switch reminder.status {
        case .scheduled, .attention: return true
        case .done, .dismissed: return false
        }
    }

    /// The read-time attention test (docs/SCHEMA.md: ".attention is derived at
    /// read time from thresholds"). A reminder demands attention when the
    /// whichever-comes-first due point is inside its window or already past -
    /// date and odometer are independent halves, so either one crossing puts
    /// the reminder in "Needs attention". Terminal rows are never re-derived.
    public static func isAttentionDue(_ reminder: Reminder,
                                      currentOdometer: Int?,
                                      now: Date) -> Bool {
        guard isActive(reminder) else { return false }
        var dateDue = false
        var odometerDue = false
        if let dueDate = reminder.dueDate {
            dateDue = daysRemaining(until: dueDate, from: now) <= attentionWindowDays
        }
        if let dueOdometer = reminder.dueOdometer,
           let km = kmRemaining(until: dueOdometer, from: currentOdometer) {
            odometerDue = km <= attentionWindowKm
        }
        return dateDue || odometerDue
    }

    /// The stored-transition status: `.attention` when the read-time test is
    /// true, `.scheduled` otherwise, and unchanged for terminal rows. The
    /// caller compares against the persisted status and writes the difference
    /// so the transition is stored once, not re-derived on every recompute.
    public static func derivedStatus(_ reminder: Reminder,
                                     currentOdometer: Int?,
                                     now: Date) -> ReminderStatus {
        switch reminder.status {
        case .scheduled, .attention:
            return isAttentionDue(reminder, currentOdometer: currentOdometer, now: now)
                ? .attention
                : .scheduled
        case .done, .dismissed:
            return reminder.status
        }
    }

    // MARK: - Complete

    /// The COMPLETE transition. `entryId` is the bookkeeping the completion
    /// produced (`.done(entryId)`); pass nil for a declined cost prompt
    /// (`.done(nil)` - completion never forces bookkeeping). The next
    /// occurrence, when recurrence is set, anchors at `completionDate` /
    /// `completionOdometer`, NOT the original due - that is the no-drift rule.
    /// When everyKm is set but no completion odometer is known, the km half
    /// cannot anchor and only the date half carries over; if no half anchors
    /// at all, no next row is created (a reminder with neither due field is
    /// not a reminder, so fabricating one would be worse than not creating it).
    /// A terminal row (`.done`/`.dismissed`) is left untouched: completing
    /// history twice must not duplicate the next occurrence.
    public static func complete(_ reminder: Reminder,
                                entryId: UUID?,
                                completionDate: Date,
                                completionOdometer: Int?,
                                now: Date = Date()) -> CompleteResult {
        guard isActive(reminder) else {
            return CompleteResult(completed: reminder, nextOccurrence: nil)
        }

        var completed = reminder
        completed.updatedAt = now
        completed.status = .done(entryId: entryId)

        var nextOccurrence: Reminder?
        if let recurrence = reminder.recurrence {
            var nextDate: Date?
            var nextOdometer: Int?
            if let months = recurrence.everyMonths, months > 0 {
                nextDate = Calendar.current.date(byAdding: .month, value: months, to: completionDate)
            }
            if let km = recurrence.everyKm, km > 0, let completionOdometer {
                nextOdometer = completionOdometer + km
            }
            if nextDate != nil || nextOdometer != nil {
                nextOccurrence = Reminder(
                    id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                    vehicleId: reminder.vehicleId,
                    title: reminder.title,
                    category: reminder.category,
                    dueDate: nextDate,
                    dueOdometer: nextOdometer,
                    recurrence: recurrence,
                    sourceEntryId: entryId,
                    status: .scheduled)
            }
        }

        return CompleteResult(completed: completed, nextOccurrence: nextOccurrence)
    }

    // MARK: - Reschedule

    /// The RESCHEDULE transition: edits dueDate/dueOdometer in place, and a
    /// fired `.attention` resets to `.scheduled` so it can notify again
    /// (docs/SCHEMA.md). Terminal rows (history) cannot be rescheduled - the
    /// row comes back unchanged.
    public static func reschedule(_ reminder: Reminder,
                                  dueDate: Date?,
                                  dueOdometer: Int?,
                                  now: Date = Date()) -> Reminder {
        guard isActive(reminder) else { return reminder }
        var updated = reminder
        updated.updatedAt = now
        updated.dueDate = dueDate
        updated.dueOdometer = dueOdometer
        if updated.status == .attention {
            updated.status = .scheduled
        }
        return updated
    }

    // MARK: - Dismiss

    /// The DISMISS-with-reason transition, deliberately distinct from delete
    /// (docs/SCHEMA.md): the row survives with its reason and feeds
    /// anomaly/insight logic ("dismissed: sold the tires"). `reason` is
    /// optional - dismissing without a stated reason is still a dismissal, not
    /// a deletion.
    public static func dismiss(_ reminder: Reminder,
                               reason: String?,
                               now: Date = Date()) -> Reminder {
        var updated = reminder
        updated.updatedAt = now
        updated.status = .dismissed(reason: reason)
        return updated
    }
}
