import Foundation

/// One terminal reminder (`.done` / `.dismissed`) as a History row (RV.248,
/// docs/JOURNEYS.md J7c -> "Delete", docs/SCREENMAP.md -> "Reminders across
/// cars"). The live lists drop terminal rows by construction; this is the one
/// place they are read back, so the dismissal reason the screen collects and
/// the entry a completion produced stop being write-only data.
public struct ReminderHistoryRow: Equatable, Sendable, Identifiable {
    public let reminder: Reminder
    /// How many times a reminder with this title has been COMPLETED on this
    /// car, this row included. 0 for a dismissed row (a dismissal is not a
    /// completion). This is the honest version of J7c's "oil changed 3x on
    /// time": the log records that a completion happened, never whether it
    /// landed before the due point, so "on time" is not a claim the data can
    /// support.
    public let completionCount: Int

    public init(reminder: Reminder, completionCount: Int) {
        self.reminder = reminder
        self.completionCount = completionCount
    }

    public var id: UUID { reminder.id }
}

/// The read side of the reminder lifecycle (RV.248). `ReminderLifecycle` owns
/// the transitions; this type answers what a terminal row carries, so the L1
/// table tests without a simulator and the History view renders the same
/// values the tests assert.
public enum ReminderHistory {

    /// The entry a `.done` completion logged, or nil for a dismissed row and a
    /// completion that skipped bookkeeping (`.done(nil)`).
    public static func completedEntryId(of reminder: Reminder) -> UUID? {
        if case .done(let entryId) = reminder.status { return entryId }
        return nil
    }

    /// The reason a dismissed reminder carries, trimmed; nil when it was
    /// dismissed without one. A whitespace-only reason is not a reason.
    public static func dismissalReason(of reminder: Reminder) -> String? {
        guard case .dismissed(let reason) = reminder.status else { return nil }
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Completed occurrences of `reminder`'s title on its own car, among the
    /// terminal rows. 0 for a row that is not `.done`. Titles are compared
    /// exactly: the count groups the user's own repeated completions, never a
    /// fuzzy match that could merge two different jobs.
    public static func completionCount(of reminder: Reminder,
                                       among terminal: [Reminder]) -> Int {
        guard case .done = reminder.status else { return 0 }
        return terminal.filter { candidate in
            guard candidate.vehicleId == reminder.vehicleId,
                  case .done = candidate.status else { return false }
            return candidate.title == reminder.title
        }.count
    }

    /// The terminal rows as history rows, preserving the caller's order (the
    /// repository query orders most recent first) and computing each row's
    /// completion count over the whole set. Active rows are filtered out here
    /// as well as in the query, so a caller that hands over the wrong set
    /// cannot render live work as history.
    public static func rows(_ terminal: [Reminder]) -> [ReminderHistoryRow] {
        terminal
            .filter { !ReminderLifecycle.isActive($0) }
            .map { reminder in
                ReminderHistoryRow(reminder: reminder,
                                   completionCount: completionCount(of: reminder,
                                                                    among: terminal))
            }
    }
}
