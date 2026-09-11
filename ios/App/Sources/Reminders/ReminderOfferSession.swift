import Foundation
import Observation
import TankbookCore

/// Carries a post-save reminder offer from an entry screen's save path to the
/// tab root that presented that screen (RV.77, docs/JOURNEYS.md J7d "Just did
/// it"). The entry screen stages the proposal as the LAST step of a successful
/// save; the tab root, once its service/expense sheet has fully dismissed,
/// presents `ServiceReminderOfferSheet`.
///
/// Mirrors `ReminderCompletionSession`: a single in-memory hand-off, cleared on
/// consume so a stale offer can never pop over an unrelated later dismissal.
@MainActor
@Observable
final class ReminderOfferSession {
    /// The offer awaiting presentation, or nil. Set by a service/expense save
    /// path; moved to `presented` once the tab root is ready to show it.
    var pending: ReminderOffer.Proposal?

    /// The offer currently presented by a tab root (drives the sheet). Cleared
    /// when the sheet is dismissed (Create / Not this time).
    var presented: ServiceReminderOfferTarget?

    /// Moves the staged offer onto the presentation slot. Called from the tab
    /// root's route-sheet `onDismiss`, so the offer presents only after the
    /// entry sheet is fully gone - never mid-save, never over the saved sheet.
    func promote() {
        guard presented == nil, let proposal = pending else { return }
        pending = nil
        presented = ServiceReminderOfferTarget(proposal: proposal)
    }

    /// Clears a stale staged offer the moment a NEW sheet is presented - an
    /// offer is only ever the successor of the save that staged it, never a
    /// sheet that opens later (hard rule 7: nothing appears over an unrelated
    /// action). The sheet that staged its own offer dismisses without
    /// re-presenting its content builder, so its offer survives to `promote`.
    func clearStale() {
        pending = nil
    }

    /// Stages the offer a just-saved ServiceRecord warrants (RV.77). Called
    /// once the record is on disk and NOT as part of completing an existing
    /// reminder (that flow schedules its own next cycle).
    ///
    /// A mount record's offer is titled with the mounted set's own name, so the
    /// set is looked up here - the pure `ReminderOffer` only sees the record.
    /// When a swap reminder is proposed, a shape-only event records it: a
    /// reminder that silently fails to schedule must not look like one nobody
    /// accepted (docs/LOGGING.md, hard rule 12).
    func stage(afterService service: ServiceRecord,
               repository: TankbookRepository) {
        let live = (try? repository.liveReminders(forVehicle: service.vehicleId)) ?? []
        let tireSetName = service.tireSetId.flatMap { id in
            (try? repository.liveTireSets(forVehicle: service.vehicleId))?
                .first { $0.id == id }?.name
        }
        let proposal = ReminderOffer.propose(afterService: service,
                                             tireSetName: tireSetName,
                                             liveReminders: live)
        pending = proposal
        if proposal?.category == .tires {
            AppLog.shared.emit(SwapReminderProposal(outcome: .proposed))
        }
    }

    /// Stages the offer a just-saved Expense warrants (RV.77). Insurance is the
    /// one recurring Expense category; a plain save proposes, a
    /// reminder-completion hand-off does not.
    func stage(afterExpense expense: Expense,
               repository: TankbookRepository) {
        let live = (try? repository.liveReminders(forVehicle: expense.vehicleId)) ?? []
        pending = ReminderOffer.propose(afterExpense: expense, liveReminders: live)
    }
}

/// The `Identifiable` payload a tab root presents via `.sheet(item:)`.
struct ServiceReminderOfferTarget: Identifiable {
    let proposal: ReminderOffer.Proposal
    var id: String { "\(proposal.vehicleId.uuidString).\(proposal.sourceEntryId.uuidString)" }
}
