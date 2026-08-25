import Foundation

/// The save-ready shape of the Reminder form (docs/SCHEMA.md -> Reminder,
/// docs/JOURNEYS.md J7c). The typed screen holds raw text; this value type is
/// the decision layer between those strings and the persisted `Reminder`, and
/// every rule here tests without a simulator (docs/TESTING.md, L1) - the same
/// pattern as `ServiceEntryDraft`.
///
/// The one invariant the form exists for: **neither due field is mandatory on
/// its own, but a reminder with neither is not a reminder.** A date-only or an
/// odometer-only reminder is a perfectly good reminder; a title-only one
/// refuses to save and names its next step (hard rule 7).
public struct ReminderDraft: Equatable, Sendable {
    public var title: String
    public var category: ReminderCategory
    public var dueDate: Date?
    public var dueOdometer: Int?
    public var recurrenceEveryKm: Int?
    public var recurrenceEveryMonths: Int?

    public init(title: String, category: ReminderCategory,
                dueDate: Date? = nil, dueOdometer: Int? = nil,
                recurrenceEveryKm: Int? = nil, recurrenceEveryMonths: Int? = nil) {
        self.title = title
        self.category = category
        self.dueDate = dueDate
        self.dueOdometer = dueOdometer
        self.recurrenceEveryKm = recurrenceEveryKm
        self.recurrenceEveryMonths = recurrenceEveryMonths
    }

    /// Whether the form can save, as a decision the view and its tests share.
    public enum SaveReadiness: Equatable, Sendable {
        case ready
        /// The title is blank: nothing to call the reminder.
        case titleMissing
        /// Neither due field is set: a reminder without a due date or a due
        /// odometer is not a reminder.
        case noDueField
    }

    public var readiness: SaveReadiness {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .titleMissing
        }
        if dueDate == nil && dueOdometer == nil {
            return .noDueField
        }
        return .ready
    }

    /// The recurrence rule, nil when neither half is set. A zero is treated as
    /// unset (entering "0" in a recurrence field is a no-op, not a burst).
    public var recurrence: Reminder.Recurrence? {
        let km = recurrenceEveryKm.flatMap { $0 > 0 ? $0 : nil }
        let months = recurrenceEveryMonths.flatMap { $0 > 0 ? $0 : nil }
        if km == nil && months == nil { return nil }
        return Reminder.Recurrence(everyKm: km, everyMonths: months)
    }

    /// Builds the new `Reminder` row the repository persists - THE create path,
    /// shared by the form and the L1 tests so they exercise the same
    /// conversion. A draft that is not `.ready` still builds (callers gate
    /// save on `readiness`); the produced row would violate the reminder
    /// invariant, which is the caller's bug to refuse.
    public func build(vehicleId: UUID, now: Date = Date()) -> Reminder {
        Reminder(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, title: title, category: category,
            dueDate: dueDate, dueOdometer: dueOdometer,
            recurrence: recurrence, sourceEntryId: nil, status: .scheduled)
    }

    /// The edit/reschedule path: applies the form's decisions to an existing
    /// reminder in place, keeping its id, creation stamp and sourceEntryId.
    /// A fired `.attention` resets to `.scheduled` (docs/SCHEMA.md: "a fired
    /// .attention resets so it can notify again"); the list's read-time
    /// derivation re-arms it on the next load if it is still due.
    /// `.done`/`.dismissed` rows keep their status - history is never edited
    /// back into the active list through the form.
    public func applied(to existing: Reminder, now: Date = Date()) -> Reminder {
        var updated = existing
        updated.updatedAt = now
        updated.title = title
        updated.category = category
        updated.dueDate = dueDate
        updated.dueOdometer = dueOdometer
        updated.recurrence = recurrence
        if updated.status == .attention {
            updated.status = .scheduled
        }
        return updated
    }
}
