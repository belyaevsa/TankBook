import Foundation
import Observation
import TankbookCore
import UIKit

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
///
/// PJ.29a: the session also owns the CLOUD reading of the same first page
/// (`gateway`), started by the capture path once the local split has produced
/// its outcome. The one save boundary seals both reads: a cloud answer that
/// lands after the save routes to the inbox, never to the editor (hard rule 13).
@MainActor
@Observable
final class ServiceInvoiceSession {
    var pendingPrefill: ServiceEntryPrefill?
    /// Bumped whenever a deferred read fills the open form after `load()`, so the
    /// view can apply a pre-fill that arrived late (the non-Equatable pages ride
    /// along, so the pre-fill itself cannot be an `onChange` trigger).
    private(set) var prefillRevision = 0

    @ObservationIgnored private let deferred = DeferredRecognition()

    /// PJ.29a: the cloud reading for the current scan. Owned here, not by the
    /// sheet, because the CAPTURE starts it the moment the local split lands -
    /// the sheet may not exist yet. A fresh instance per scan, since
    /// `GatewayScanSession.start` is one-shot.
    var gateway = GatewayScanSession()
    /// The cloud answer that arrived within the budget, waiting for the open
    /// sheet to apply it. The sheet consumes it and bumps `gatewayRevision`;
    /// `nil` once applied.
    var pendingGatewayExtraction: GatewayExtraction?
    /// Bumped when a cloud answer is ready, so the sheet can apply it (the
    /// answer is not `Equatable`-triggerable on its own).
    private(set) var gatewayRevision = 0
    /// The record a cloud read is about, once the user saves. It exists so a
    /// gateway started AFTER the save (a very slow local split can delay
    /// `startGateway` past `markSaved`) still knows the record is already saved
    /// and routes its late answer to the inbox rather than to a sheet that is
    /// gone.
    @ObservationIgnored private var gatewaySavedEntryID: UUID?

    /// Starts one deferred read (RV.215). The session decides by the save
    /// boundary whether the outcome fills the open form (`onAnswer`) or becomes
    /// an inbox item (`onSavedAnswer`), so no caller re-derives it.
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
    /// inbox; one that already answered keeps the form it filled. Both the
    /// local split and the cloud reading share the one save boundary, so one
    /// call seals both (PJ.29a).
    func markSaved(entryID: UUID) {
        deferred.markSaved(entryID: entryID)
        gatewaySavedEntryID = entryID
        gateway.markSaved(entryID: entryID)
    }

    /// PJ.29a: starts the cloud reading of the same scan, under the same guards
    /// the fill-up and expense paths use (`allowsServerBacked` is the caller's,
    /// a transport and a JPEG are checked here). The answer is delivered to the
    /// open sheet through `pendingGatewayExtraction`/`gatewayRevision`; a late
    /// answer is routed by `onSavedAnswer`, never applied to the editor (hard
    /// rule 13).
    ///
    /// A fresh `GatewayScanSession` per scan: `start` is one-shot, so a second
    /// scan must not inherit the first's started state.
    func startGateway(image: UIImage,
                      hints: GatewayExtractHints,
                      captureId: String,
                      transport injectedTransport: (any GatewayExtractTransport)? = nil,
                      onSavedAnswer: @escaping @MainActor (GatewayExtraction, UUID) -> Void) {
        gateway = GatewayScanSession()
        guard let cgImage = image.cgImage,
              let transport = injectedTransport ?? GatewayScanStarter.makeTransport(),
              let jpeg = GatewayRendition.jpegData(from: cgImage) else { return }
        let request = GatewayExtractRequest(kind: "invoice",
                                            imageJPEG: jpeg,
                                            hints: hints,
                                            captureId: captureId)
        gateway.start(transport: transport, request: request) { [weak self] extraction in
            guard let self else { return }
            self.pendingGatewayExtraction = extraction
            self.gatewayRevision += 1
        } onSavedAnswer: { extraction, entryID in
            onSavedAnswer(extraction, entryID)
        }
        // A gateway started after the save (a slow local split delayed this
        // call) must still treat its answer as late.
        if let savedEntryID = gatewaySavedEntryID {
            gateway.markSaved(entryID: savedEntryID)
        }
    }

    /// The sheet consumed the pending cloud answer. One-shot, like the local
    /// pre-fill: a second open must not re-apply a stale reading.
    func consumePendingGatewayExtraction() -> GatewayExtraction? {
        defer { pendingGatewayExtraction = nil }
        return pendingGatewayExtraction
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
    /// PJ.29a: the cloud reading is cancelled with it - a late answer would
    /// only re-offer values for a record that was never written.
    func discard() {
        deferred.cancel()
        pendingPrefill = nil
        pendingGatewayExtraction = nil
        gatewaySavedEntryID = nil
        gateway = GatewayScanSession()
    }
}
