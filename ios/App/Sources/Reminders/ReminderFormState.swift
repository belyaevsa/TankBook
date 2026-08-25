import Foundation
import TankbookCore

/// Everything the Reminder form collects, plus the derived decisions that gate
/// Save (docs/SCHEMA.md -> Reminder). The raw strings live here; the decisions
/// - whether the draft may save and why - live in the pure `ReminderDraft` so
/// the view, its L1 tests and the L4 tests all share one gate. This is the
/// same two-layer pattern as ServiceEntry (ServiceEntryFormState ->
/// ServiceEntryDraft).
struct ReminderFormState: Equatable {
    var title = ""
    var category: ReminderCategory = .oil
    var hasDueDate = false
    var dueDate = Date()
    var dueOdometer = ""
    var recurrenceEveryMonths = ""
    var recurrenceEveryKm = ""

    // Snapshots for the discard guard (SCREENMAP rule 1): the form is dirty
    // only for real edits. The pre-fill from an existing reminder is a
    // convenience default, exactly as on ServiceEntry.
    var initialTitle = ""
    var initialCategory: ReminderCategory = .oil
    var initialHasDueDate = false
    var initialDueDate = Date()
    var initialDueOdometer = ""
    var initialRecurrenceEveryMonths = ""
    var initialRecurrenceEveryKm = ""

    // MARK: - Parsed values

    var odometerValue: Int? {
        Self.integer(from: dueOdometer)
    }

    var monthsValue: Int? {
        Self.integer(from: recurrenceEveryMonths)
    }

    var kmValue: Int? {
        Self.integer(from: recurrenceEveryKm)
    }

    private static func integer(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(OdometerFormat.ungrouped(trimmed))
    }

    // MARK: - The save decision (delegates to the pure draft)

    var draft: ReminderDraft {
        ReminderDraft(title: title, category: category,
                      dueDate: hasDueDate ? dueDate : nil,
                      dueOdometer: odometerValue,
                      recurrenceEveryKm: kmValue,
                      recurrenceEveryMonths: monthsValue)
    }

    var readiness: ReminderDraft.SaveReadiness {
        draft.readiness
    }

    // MARK: - Edit pre-fill

    /// Populates the form from an existing reminder for the edit/reschedule
    /// path. Every value lands as a user-editable default (hard rule 13).
    static func from(reminder: Reminder) -> ReminderFormState {
        var state = ReminderFormState()
        state.title = reminder.title
        state.category = reminder.category
        state.hasDueDate = reminder.dueDate != nil
        state.dueDate = reminder.dueDate ?? Date()
        state.dueOdometer = reminder.dueOdometer.map(OdometerFormat.grouped) ?? ""
        state.recurrenceEveryMonths = reminder.recurrence?.everyMonths.map(String.init) ?? ""
        state.recurrenceEveryKm = reminder.recurrence?.everyKm.map { OdometerFormat.grouped($0) } ?? ""
        state.snapshotInitials()
        return state
    }

    mutating func snapshotInitials() {
        initialTitle = title
        initialCategory = category
        initialHasDueDate = hasDueDate
        initialDueDate = dueDate
        initialDueOdometer = dueOdometer
        initialRecurrenceEveryMonths = recurrenceEveryMonths
        initialRecurrenceEveryKm = recurrenceEveryKm
    }

    // MARK: - Discard guard

    /// Real edits only: a typed title, a category move, a due date added/
    /// removed/moved, an odometer or a recurrence field changed. Opening the
    /// form and closing it with just the pre-fills discards silently.
    func hasEdits() -> Bool {
        if title != initialTitle { return true }
        if category != initialCategory { return true }
        if hasDueDate != initialHasDueDate { return true }
        if hasDueDate, !Calendar.current.isDate(dueDate, inSameDayAs: initialDueDate) { return true }
        if odometerValue != Self.integer(from: initialDueOdometer) { return true }
        if monthsValue != Self.integer(from: initialRecurrenceEveryMonths) { return true }
        if kmValue != Self.integer(from: initialRecurrenceEveryKm) { return true }
        return false
    }
}
