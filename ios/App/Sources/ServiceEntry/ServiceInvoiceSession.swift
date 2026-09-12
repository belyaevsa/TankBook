import Foundation
import Observation
import TankbookCore

/// What one scanned invoice produces: the pre-fill the open form consumes and
/// the recognition a late read offers the saved entry. The two travel together
/// because they come from the same split - the pre-fill is the user's head
/// start, the recognition is what the inbox compares against once the entry is
/// saved (RV.215).
struct ServiceScanOutcome {
    let prefill: ServiceEntryPrefill
    let recognition: ServiceRecognition
}

/// Carries the just-scanned invoice pre-fill from the Capture flow into the
/// ServiceEntry sheet (P3.1b). Capture processes the scanned pages and writes
/// the result here; ServiceEntry reads it on load. A single in-memory hand-off
/// - the pre-fill is default input the user edits (hard rule 13), never a
/// second screen, so nothing is persisted until the user saves.
///
/// RV.215: the read is DEFERRED. `start` runs it in the background while the
/// form opens on whatever is available; a read that finishes before the entry
/// is saved fills the open form, and one that finishes after `markSaved` becomes
/// an inbox item through `GatewayInboxPolicy.item` - the same one policy the
/// fuel path uses. The boundary is the save (`DeferredRecognition`), never a
/// second producer.
@MainActor
@Observable
final class ServiceInvoiceSession {
    var pendingPrefill: ServiceEntryPrefill?
    /// Bumped whenever a deferred read fills the open form after `load()`, so the
    /// view can apply a pre-fill that arrived late (the non-Equatable pages ride
    /// along, so the pre-fill itself cannot be an `onChange` trigger).
    private(set) var prefillRevision = 0

    @ObservationIgnored private let deferred = DeferredRecognition()

    /// Starts one deferred read. `onAnswer` fills the open form; `onSavedAnswer`
    /// records the late recognition in the inbox. The session decides which by
    /// the save boundary, so no caller re-derives it.
    func start(work: @escaping @MainActor () async -> ServiceScanOutcome,
               onAnswer: @escaping @MainActor (ServiceScanOutcome) -> Void,
               onSavedAnswer: @escaping @MainActor (ServiceScanOutcome, UUID) -> Void) {
        deferred.start { [weak self] token in
            let outcome = await work()
            guard let self, self.deferred.generation == token else { return }
            if let entryID = self.deferred.savedEntryID {
                onSavedAnswer(outcome, entryID)
            } else {
                onAnswer(outcome)
                self.prefillRevision += 1
            }
        }
    }

    /// RV.243: starts the read with the pages already persisted. They are staged
    /// BEFORE the read runs, so a save that beats the read keeps the invoice
    /// (hard rule 8); the read enriches the same pages and only offers values.
    /// A caller with no pages (the L1 session tests) uses `start(work:...)`.
    func start(stagedPages: [InvoicePage],
               work: @escaping @MainActor () async -> ServiceScanOutcome,
               onAnswer: @escaping @MainActor (ServiceScanOutcome) -> Void,
               onSavedAnswer: @escaping @MainActor (ServiceScanOutcome, UUID) -> Void) {
        stagePages(stagedPages)
        start(work: work, onAnswer: onAnswer, onSavedAnswer: onSavedAnswer)
    }

    /// The entry was saved. A read still in flight is late and routes to the
    /// inbox; one that already answered keeps the form it filled.
    func markSaved(entryID: UUID) {
        deferred.markSaved(entryID: entryID)
    }

    /// RV.243: stages the pages persisted at scan start, before the read has
    /// produced any values, so the open form carries the invoice even when the
    /// read is still in flight at save (hard rule 8). The read replaces this
    /// with the same pages plus the values it resolved (`start`'s `onAnswer`);
    /// the values are the read's delivery, the pages are the capture's.
    func stagePages(_ pages: [InvoicePage]) {
        guard !pages.isEmpty else { return }
        pendingPrefill = ServiceEntryPrefill(pages: pages, provenance: .receiptScan)
    }

    /// RV.245: the sheet closed without a save. The in-flight read is cancelled
    /// (its answer would only re-offer pages the cleanup is about to delete)
    /// and the staged pre-fill cleared, so a later open starts clean. The
    /// caller removes the page rows and files; this only owns the hand-off.
    func discard() {
        deferred.cancel()
        pendingPrefill = nil
    }
}
