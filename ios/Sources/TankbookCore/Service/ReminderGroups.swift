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
    /// The number of rows that demand attention (RV.76's Home row count): how
    /// many reminders need the user, ACROSS every live car. This is the count
    /// `grouped(rows).attention.count` by a name, so the count and the merged
    /// list's "Needs attention" group are the same number by construction and
    /// can never disagree. Derived at read time (hard rule 2): it is a pure
    /// function over the live rows, never stored, never seeded.
    public static func attentionCount(_ rows: [ReminderListRow],
                                      now: Date = Date()) -> Int {
        grouped(rows, now: now).attention.count
    }

    /// The attention count for ONE vehicle (RV.79: the per-car badge on a
    /// Garage / Car switcher row) - how many of ITS live reminders need the
    /// user NOW, judged against the vehicle's OWN current odometer, never a
    /// shared reading, exactly as the merged list judges each of its rows.
    ///
    /// Derived at read time (hard rule 2): a pure function over the caller's
    /// live reminders, never stored, never seeded as a number, never cached on
    /// the row. It is defined as "the merged list's 'Needs attention' group for
    /// that vehicle" - the caller passes the SAME live rows the merged list
    /// would group (`liveRemindersAcrossVehicles`), so the badge and the list
    /// can never disagree about what is due. Terminal rows (`.done` /
    /// `.dismissed`) never count, and a row whose only due half cannot be
    /// judged (an odometer reminder on a car with no reading) is not attention.
    public static func attentionCount(forVehicle vehicleId: UUID,
                                      among reminders: [Reminder],
                                      currentOdometer: Int?,
                                      now: Date = Date()) -> Int {
        reminders.filter {
            $0.vehicleId == vehicleId
                && ReminderLifecycle.isAttentionDue($0,
                                                    currentOdometer: currentOdometer,
                                                    now: now)
        }.count
    }

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
