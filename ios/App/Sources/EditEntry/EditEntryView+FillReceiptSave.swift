import Foundation
import TankbookCore

// RV.204: the fill-up edit's receipt half, split out so the degrade contract is
// L1-testable the same way the non-fill save's is
// (`writeNonFillWithHeldReceipt`, EditEntryView+NonFillSave.swift). Both entry
// kinds must obey ONE contract when a photo write fails: the save the user asked
// for lands, the failure is reported after it, and re-attach is the next step
// (docs/ERRORS.md -> Edit entry, the RV.204 row). Neither blocks.

extension EditEntryView {

    /// Attempts the held receipt photo's write for a fill-up edit and returns
    /// the `FillUp` to persist plus the write outcome. The write goes through
    /// the SAME `attemptReceiptPhotoWrite` seam the Confirm save and the
    /// non-fill save use, so a failure degrades to no photo and surfaces as
    /// `.lost` - never a throw that blocks the entry (hard rule 1) and never a
    /// silent drop (hard rule 8).
    ///
    /// A landed photo is **appended** to the entry's existing attachment list,
    /// never a replace (RV.204's sibling decision): a reference the user has not
    /// removed - a dangling id from an earlier failed write, say (RV.208) - is
    /// left for the missing-photo card to surface, exactly as the non-fill save
    /// leaves it. The extraction record is written only when the photo landed,
    /// so the entry never claims a receipt the disk did not get.
    @MainActor
    static func attachHeldReceiptToFill(
        _ updated: FillUp,
        saved: ScannedSaveValues,
        heldPhoto: HeldReceiptPhoto?,
        repository: TankbookRepository
    ) -> (fill: FillUp, outcome: ReceiptWriteOutcome) {
        var target = updated
        var outcome = ReceiptWriteOutcome.nothingToWrite
        if let heldPhoto {
            // The photo is kept either way: if the OCR has not settled yet, the
            // attach still writes the photo with an empty extraction rather than
            // dropping it. The empty extraction still mints the shared id, so
            // the write is attempted and its failure is reported (an all-nil
            // `FuelExtraction` is not the typed path - `hasPhoto: true`).
            let plan = ScannedSavePlanner.plan(
                extraction: heldPhoto.extraction ?? FuelExtraction(),
                cropRects: [:],
                qrAnchor: nil,
                declaredProvenance: .manual,
                hasPhoto: true,
                saved: saved,
                pipeline: heldPhoto.isPumpDisplay
                    ? ScannedSavePlanner.pumpReaderPipeline : ScannedSavePlanner.onDevicePipeline)
            var source = ConfirmPrefill(extraction: heldPhoto.extraction,
                                        ocrLines: heldPhoto.ocrLines,
                                        sourceImage: heldPhoto.image)
            if heldPhoto.isPumpDisplay { source.provenance = .pumpPhoto }
            outcome = attemptReceiptPhotoWrite(scanned: plan, source: source,
                                               repository: repository)
            target.attachments = updated.attachments + outcome.sharedIDs
            // The recorded values are the entry's first photo's. A page added
            // to an entry that already carries them (the back of the receipt,
            // a second page) is kept as a photo and never replaces them.
            if outcome.sharedID != nil, updated.extraction == nil {
                target.extraction = plan.extraction
            }
        }
        return (target, outcome)
    }

    /// Every held page, written in the order the user added them, each through
    /// the one-page seam above - so each degrades on its own and a lost page
    /// never costs the pages around it (RV.331).
    @MainActor
    static func attachHeldReceiptsToFill(
        _ updated: FillUp,
        saved: ScannedSaveValues,
        heldPhotos: [HeldReceiptPhoto],
        repository: TankbookRepository
    ) -> (fill: FillUp, outcomes: [ReceiptWriteOutcome]) {
        var target = updated
        var outcomes: [ReceiptWriteOutcome] = []
        for held in heldPhotos {
            let (next, outcome) = attachHeldReceiptToFill(target, saved: saved, heldPhoto: held,
                                                          repository: repository)
            target = next
            outcomes.append(outcome)
        }
        return (target, outcomes)
    }
}
