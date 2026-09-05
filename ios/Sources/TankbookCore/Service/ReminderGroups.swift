import Foundation

/// One reminder as a row in a Reminders list, carrying the odometer context of
/// ITS OWN vehicle. The merged "all cars" list (RV.75) renders several vehicles
/// at once, and each car has its own current reading, so the km half of every
/// row - its attention test, its caption, its progress, its sort key - must be
/// judged against that row's car, never a single shared odometer. The per-car
/// list is simply the special case where every row shares one car's reading.
public struct ReminderListRow: Equatable, Sendable, Identifiable {
    public let reminder: Reminder
    /// The current odometer of `reminder.vehicleId`'s car. `nil` when the car
    /// has no reading (no entries and no initial odometer) - the km half of an
    /// odometer reminder cannot be evaluated then, exactly as
    /// `ReminderLifecycle.kmRemaining` defines it.
    public let currentOdometer: Int?

    public init(reminder: Reminder, currentOdometer: Int?) {
        self.reminder = reminder
        self.currentOdometer = currentOdometer
    }

    public var id: UUID { reminder.id }
}

/// The two display groups of a Reminders list (docs/SCREENMAP.md -> "Reminders
/// across cars"): "Needs attention" then "Scheduled", each sorted so a date
/// reminder and an odometer reminder interleave by urgency - a merged row that
/// sorted by car first would answer "which car" instead of "what needs me".
///
/// This is the ONLY place a list's group and order are decided, so the per-car
/// screen and the merged screen cannot drift apart, and the lifecycle rules are
/// never duplicated: the attention test and the sort key come from the existing
/// `ReminderLifecycle` (`.attention` is derived at read time from the same
/// thresholds; terminal `.done`/`.dismissed` rows never re-derive). A row that
/// is not attention is scheduled by complement - the two groups cover every
/// active reminder exactly once.
public enum ReminderListGroups {

    /// Partitions the active rows into the two groups and sorts each by
    /// whichever-comes-first due point (soonest first, oldest `createdAt`
    /// breaking a tie - the list's own rule and `ReminderBanner`'s).
    public static func grouped(_ rows: [ReminderListRow],
                               now: Date = Date()) -> (attention: [ReminderListRow],
                                                       scheduled: [ReminderListRow]) {
        let attention = rows.filter {
            ReminderLifecycle.isAttentionDue($0.reminder,
                                             currentOdometer: $0.currentOdometer,
                                             now: now)
        }
        let scheduled = rows.filter {
            !ReminderLifecycle.isAttentionDue($0.reminder,
                                              currentOdometer: $0.currentOdometer,
                                              now: now)
        }
        return (attention.sorted { sooner($0, $1, now: now) },
                scheduled.sorted { sooner($0, $1, now: now) })
    }

    /// The urgency order over two rows: the one whose due point is sooner
    /// first; `createdAt` breaks the tie so the order is total and stable.
    static func sooner(_ lhs: ReminderListRow, _ rhs: ReminderListRow,
                       now: Date) -> Bool {
        let lhsKey = ReminderLifecycle.due(lhs.reminder)?
            .dueSortKey(currentOdometer: lhs.currentOdometer, now: now) ?? .max
        let rhsKey = ReminderLifecycle.due(rhs.reminder)?
            .dueSortKey(currentOdometer: rhs.currentOdometer, now: now) ?? .max
        if lhsKey == rhsKey { return lhs.reminder.createdAt < rhs.reminder.createdAt }
        return lhsKey < rhsKey
    }
}
