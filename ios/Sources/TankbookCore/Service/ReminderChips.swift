import Foundation

// MARK: - The Home reminder strip (RV.122, docs/JOURNEYS.md J7c)

/// One chip on Home: a due reminder and the measure that puts it there - the
/// days to a date, the kilometres to an odometer, or the odometer alone when
/// the car's current reading is unknown. `isOverdue` is a fact the words
/// carry; the chip stays amber either way (hard rule 5: red lives only in
/// system dialogs).
public struct ReminderChip: Equatable, Sendable, Identifiable {
    public enum Measure: Equatable, Sendable {
        /// A date reminder: negative when past.
        case days(Int)
        /// A distance reminder against the current odometer: negative when past.
        case km(Int)
        /// A distance reminder with no current odometer to measure from.
        case dueAtOdometer(Int)
    }

    public let reminder: Reminder
    public let measure: Measure

    public var id: UUID { reminder.id }

    public var isOverdue: Bool {
        switch measure {
        case .days(let days): return days < 0
        case .km(let km): return km < 0
        case .dueAtOdometer: return false
        }
    }
}

/// What the strip shows: the due reminders as chips, then the door. Empty
/// when nothing is due - the strip vanishes rather than saying "nothing"
/// (docs/ERRORS.md -> Home).
public enum ReminderChipItem: Equatable, Sendable, Identifiable {
    case reminder(ReminderChip)
    /// The last chip, always: the door to the merged all-cars list.
    case allReminders

    public var id: String {
        switch self {
        case .reminder(let chip): return chip.id.uuidString
        case .allReminders: return "all"
        }
    }
}

public enum ReminderChips {
    /// The strip for a car: every attention-due active reminder (the same
    /// derivation the list's "Needs attention" group and the old banner used -
    /// hard rule 2, derived at read time) in due order, soonest first, ties by
    /// `createdAt`; then `.allReminders`. Nothing due yields an EMPTY list -
    /// no trailing door on its own, because the calm Reminders row is that
    /// door and an empty strip would be a warning about nothing.
    public static func items(among reminders: [Reminder], currentOdometer: Int?,
                             now: Date = Date()) -> [ReminderChipItem] {
        let due = reminders
            .filter { ReminderLifecycle.derivedStatus($0, currentOdometer: currentOdometer, now: now) == .attention }
            .sorted { lhs, rhs in
                let lhsKey = ReminderLifecycle.due(lhs)?.dueSortKey(currentOdometer: currentOdometer, now: now) ?? .max
                let rhsKey = ReminderLifecycle.due(rhs)?.dueSortKey(currentOdometer: currentOdometer, now: now) ?? .max
                if lhsKey == rhsKey { return lhs.createdAt < rhs.createdAt }
                return lhsKey < rhsKey
            }
        guard !due.isEmpty else { return [] }
        let chips = due.map { reminder -> ReminderChipItem in
            let measure = measure(reminder, currentOdometer: currentOdometer, now: now)
            return .reminder(ReminderChip(reminder: reminder, measure: measure))
        }
        return chips + [.allReminders]
    }

    /// The chip's measure: the half that is due drives it, exactly as the
    /// attention derivation picks (whichever comes first).
    static func measure(_ reminder: Reminder, currentOdometer: Int?, now: Date) -> ReminderChip.Measure {
        switch ReminderLifecycle.due(reminder) {
        case .date(let date):
            return .days(ReminderLifecycle.daysRemaining(until: date, from: now))
        case .odometer(let odometer):
            guard let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer) else {
                return .dueAtOdometer(odometer)
            }
            return .km(km)
        case .both(let date, let odometer):
            let days = ReminderLifecycle.daysRemaining(until: date, from: now)
            if let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer),
               days > ReminderLifecycle.attentionWindowDays {
                return .km(km)
            }
            return .days(days)
        case nil:
            return .days(0)
        }
    }
}
