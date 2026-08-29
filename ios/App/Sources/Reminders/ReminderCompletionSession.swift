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
        var completionDate: Date
        var completionOdometer: Int?
    }

    var pending: Pending?
}

extension ReminderCompletionSession {
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
