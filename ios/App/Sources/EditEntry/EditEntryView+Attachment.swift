import SwiftUI
import TankbookCore

// RV.37: the viewer reports a delete or replace back here. Split out of
// EditEntryView.swift to keep that file under the linter's file-length limit -
// the same reason Repository+RecentlyDeleted exists. The state it touches is
// internal for this file's reach (see EditEntryView).

extension EditEntryView {

    /// The viewer reports a delete or replace through this. The entry's
    /// attachment list is re-read from the repository (the single source of
    /// truth) WITHOUT reloading the form, so unsaved edits survive a receipt
    /// swap. When the user accepted a re-read, `extraction` is non-nil and the
    /// blank-field suggestions are applied to the form exactly as the attach
    /// flow does - dimmed, blank fields only, never a blind overwrite (hard rule
    /// 13).
    func handleAttachmentChanged(_ extraction: FuelExtraction?) {
        Task { await reloadAttachments() }
        if let extraction, let fillUp, let vehicle {
            let suggestions = ReceiptAttachMerge.suggestions(
                entry: fillForm.blankDetectingEntry(vehicle: vehicle), extraction: extraction)
            fillForm.applyAttachedSuggestions(suggestions, extraction: extraction,
                                              volumeUnit: vehicle.units.volume)
        }
    }

    /// Re-reads the entry's attachment list and the in-memory entry's
    /// `attachments` (so a later Save carries the fresh list, not the stale one
    /// it was loaded with). The form state is deliberately untouched.
    func reloadAttachments() async {
        guard let vehicle else { return }
        do {
            let repository = try AppStore.repository()
            let all = try repository.liveEntries(forVehicle: vehicle.id)
            guard let target = all.first(where: { $0.id == currentEntry?.id }) else { return }
            let ids = target.attachments
            let live = try repository.liveAttachments()
            attachments = AttachmentReference.resolved(ids, liveAttachments: live)
            missingAttachmentIDs = AttachmentReference.unresolved(ids, liveAttachments: live)
            pendingBlobIDs = Set(attachments.filter { !BlobService.isBlobAvailable($0) }.map(\.id))
            updateInMemoryAttachments(ids)
        } catch {
            AppLog.error(operation: "editEntry.reloadAttachments", category: .ui, error: error)
        }
    }

    private func updateInMemoryAttachments(_ ids: [AttachmentID]) {
        if var fill = fillUp {
            fill.attachments = ids
            fillUp = fill
        } else if var chargeCopy = charge {
            chargeCopy.attachments = ids
            charge = chargeCopy
        } else if var serviceCopy = service {
            serviceCopy.attachments = ids
            service = serviceCopy
        } else if var expenseCopy = expense {
            expenseCopy.attachments = ids
            expense = expenseCopy
        }
    }

    /// The fill-up receipt strip. An entry whose references resolve to no live
    /// `Attachment` row and that has no page yet shows the missing-photo card
    /// (RV.208 - the reference stays, the re-attach door is the next step);
    /// every other state is the one card - the saved pages, the pages held for
    /// Save, and "Add receipt" / "Add page" (RV.331). The chooser hangs off the
    /// CARD, not the screen (RV.11: iOS 26 anchors a `confirmationDialog`
    /// popover to the view it is attached to, so a screen-level attachment
    /// pointed at the middle of the form).
    @ViewBuilder
    func fillUpReceiptCard(_ fill: FillUp) -> some View {
        if attachments.isEmpty, heldPages.isEmpty, !missingAttachmentIDs.isEmpty {
            EditEntryRows.missingReceiptCard { showAttachSource = true }
                .receiptAttachSource(isPresented: $showAttachSource,
                                     title: "Add receipt") { image in
                    attachReceipt(image)
                }
        } else {
            EditEntryRows.receiptCard(attachments: attachments, entry: fill,
                                      volumeUnit: vehicle?.units.volume ?? .l,
                                      pendingBlobIDs: pendingBlobIDs,
                                      heldPages: heldPages.map(\.image),
                                      processing: attachProcessing,
                                      onAddReceipt: { showAttachSource = true },
                                      onAttachmentChanged: handleAttachmentChanged)
                .receiptAttachSource(isPresented: $showAttachSource,
                                     title: attachments.isEmpty && heldPages.isEmpty ? "Add receipt" : "Add page") { image in
                    attachReceipt(image)
                }
        }
    }

    /// One image in, held as a page for Save, with its own reading. The OCR
    /// runs through the same `CapturePipeline` the scan door uses. For a
    /// fill-up's FIRST photo the merge then decides which fields are blank on
    /// the TYPED entry, and only those are offered as dimmed pre-fills (hard
    /// rule 13); a later page (RV.331) is a photo only - it never proposes
    /// values over the ones the entry already has. A typed value is never
    /// overwritten and raises no amber (docs/ERRORS.md -> Edit entry).
    ///
    /// RV.202: shared by the fill-up and the three non-fill kinds. The
    /// blank-fields-only merge is a FILL-UP concern - a service invoice or an
    /// expense receipt has no fuel fields to pre-fill - so a non-fill attach
    /// holds the photo without any value merge. The pages are written on Save
    /// through the shared `attemptReceiptPhotoWrite` seam
    /// (`attachHeldReceiptsToFill` and `writeNonFillWithHeldReceipts`), each
    /// degrading on its own (RV.204).
    func attachReceipt(_ image: UIImage) {
        guard let vehicle else { return }
        let firstPhoto = attachments.isEmpty && heldPages.isEmpty
        let index = heldPages.count
        heldPages.append(HeldReceiptPhoto(image: image, ocrLines: [], extraction: nil))
        attachReading += 1
        Task {
            let prefill = await CapturePipeline.process(
                image,
                bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle.id),
                homeCurrency: vehicle.homeCurrency)
            let extraction = prefill.extraction ?? FuelExtraction()
            if heldPages.indices.contains(index) {
                heldPages[index].ocrLines = prefill.ocrLines
                heldPages[index].extraction = extraction
                heldPages[index].isPumpDisplay = prefill.provenance == .pumpPhoto
            }
            if firstPhoto, let fillUp {
                let suggestions = ReceiptAttachMerge.suggestions(entry: fillUp, extraction: extraction)
                fillForm.applyAttachedSuggestions(suggestions, extraction: extraction,
                                                  volumeUnit: vehicle.units.volume)
            }
            attachReading -= 1
        }
    }
}

/// Every held page's write outcome: one lost page is reported once, after the
/// entry is on disk (docs/ERRORS.md -> Edit entry, the RV.204 row).
@MainActor
func reportLostReceiptPhotos(_ outcomes: [ReceiptWriteOutcome], toastCenter: AppToastCenter) {
    if let lost = outcomes.first(where: \.lostPhoto) {
        reportLostReceiptPhoto(lost, toastCenter: toastCenter)
    }
}
