import Foundation

/// The Home banner's reminder selection (PJ.4). The banner is REAL data since
/// PJ.4 - it derives from the active reminders the same read-time derivation
/// the Reminders list uses, so production can reach it without a launch
/// argument. It is deliberately NOT a stored flag or a fixture: presence is
/// "some active reminder is attention-due", and it changes the moment a
/// reminder completes, exactly as hard rule 2's spirit demands (derived, never
/// stored).
public enum ReminderBanner {

    /// The reminder Home's banner announces: the earliest attention-due active
    /// reminder, derived via `ReminderLifecycle.derivedStatus` over the live
    /// rows - the same test the Reminders list's "Needs attention" group uses,
    /// so the two surfaces can never disagree about what is due. `nil` when
    /// nothing is due, which is also what hides the banner: there is no stored
    /// state to get out of sync.
    ///
    /// The tie-break is the list's own: the reminder whose whichever-comes-first
    /// due point is soonest, then the older `createdAt`. Terminal rows
    /// (`.done`/`.dismissed`) never re-derive (docs/SCHEMA.md), so a completed
    /// reminder drops off the banner by construction.
    public static func bannerReminder(among reminders: [Reminder],
                                      currentOdometer: Int?,
                                      now: Date = Date()) -> Reminder? {
        reminders
            .filter { ReminderLifecycle.derivedStatus($0, currentOdometer: currentOdometer, now: now) == .attention }
            .min { lhs, rhs in
                let lhsKey = ReminderLifecycle.due(lhs)?
                    .dueSortKey(currentOdometer: currentOdometer, now: now) ?? .max
                let rhsKey = ReminderLifecycle.due(rhs)?
                    .dueSortKey(currentOdometer: currentOdometer, now: now) ?? .max
                if lhsKey == rhsKey { return lhs.createdAt < rhs.createdAt }
                return lhsKey < rhsKey
            }
    }
}
