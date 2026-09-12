import Foundation
import Observation
import TankbookCore

/// Carries the "type amount" hand-off from the ReminderComplete sheet into the
/// entry screen, and back. The sheet writes a `Pending` before it opens
/// ServiceEntry/ExpenseEntry; the entry screen reads it once (to pre-fill) and
/// then completes the reminder with the entry's real id on save. The pre-fill
/// is default input the user edits (hard rule 13), so nothing is persisted
/// until the user saves.
///
/// Mirrors `ServiceInvoiceSession` / `ExpenseEntrySession`: a single in-memory
/// hand-off, never a second screen.
@MainActor
@Observable
final class ReminderCompletionSession {
    struct Pending {
        var reminder: Reminder
        /// The car the entry must be written to - the reminder's OWN car,
        /// carried explicitly so the entry's `vehicleId` cannot be decided by
        /// which car happens to be selected when the sheet opens (RV.247).
        var vehicleId: UUID
        var completionDate: Date
        var completionOdometer: Int?
    }

    var pending: Pending?
}

extension ReminderCompletionSession {
    /// The vehicle an entry opened from a completion hand-off writes to: the
    /// reminder's OWN car, resolved by id. Selection is UI state and is only the
    /// fallback for an entry opened without a hand-off; resolving from it while
    /// a hand-off is pending is how the entry landed on the wrong car (RV.247).
    /// The hand-off is a default, not a fact, but it is a default about WHICH
    /// CAR, and the entry has no editable car field - so the reminder's car wins
    /// unconditionally.
    nonisolated static func entryVehicle(vehicles: [Vehicle],
                                         pending: Pending?,
                                         selected: Vehicle?) -> Vehicle? {
        guard let pending else { return selected }
        return vehicles.first { $0.id == pending.vehicleId } ?? selected
    }

    /// Persists a completion - the completed reminder (now `.done(entryId)`
    /// history) plus, when recurrence produced one, the next occurrence - after
    /// the entry saved with `entryId`. The sheet's Skip path calls this with a
    /// nil `entryId` (`.done(nil)` - completion never forces bookkeeping), so
    /// both paths write identically through the core `ReminderCompletion`.
    static func persistCompletion(reminder: Reminder,
                                  entryId: UUID?,
                                  completionDate: Date,
                                  completionOdometer: Int?,
                                  coordinator: ReminderNotificationCoordinator) {
        do {
            let repository = try AppStore.repository()
            let result = ReminderLifecycle.complete(
                reminder, entryId: entryId,
                completionDate: completionDate,
                completionOdometer: completionOdometer)
            try ReminderCompletion.persist(result, repository: repository)
            // Completing resolves the reminder's reason: cancel its pending
            // notification, and arm the next occurrence (if recurrence created
            // one) - the coordinator's reconcile does both (docs/NOTIFICATIONS.md
            // -> Cancellation).
            let vehicleId = reminder.vehicleId
            Task { await coordinator.reconcile(vehicleId: vehicleId) }
        } catch {
            AppLog.error(operation: "reminderCompletion.persist", category: .notifications, error: error)
        }
    }
}
