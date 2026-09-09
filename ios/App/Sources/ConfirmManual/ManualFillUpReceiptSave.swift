import SwiftUI
import UIKit
import TankbookCore

// MARK: - PJ.48 + PJ.2 + RV.149 the receipt write for the Confirm sheet
//
// Everything the Confirm sheet's Save writes about the receipt photo: the
// attach-receipt row (PJ.48) and the one receipt write the scan and the attach
// share (PJ.2). Kept out of `ManualFillUpView.swift` so that file stays within
// the lint budget - the shape of a save is a peer concern to the form that
// drives it. RV.149: the write's degrade contract is a free seam here so it is
// L1-testable - a lost photo must never block the entry (hard rule 1) and must
// never be a silent drop (hard rule 8).

/// The receipt photo could not be encoded or written (PJ.2); the save degrades
/// to no photo and reports it - docs/ERRORS.md -> Confirm, the RV.149 row.
enum ReceiptAttachmentError: Error {
    case notEncodable
}

// MARK: - PJ.48 the attach-receipt row (typed path)

extension ManualFillUpView {
    /// The quiet row shows on the typed path only, and only while no photo is
    /// attached yet: a scan that carried its photo already has one, and once
    /// the user attaches, the row gives way to the save that writes it.
    var canAttachReceipt: Bool {
        prefill?.sourceImage == nil && attachedPrefill == nil
    }

    /// The quiet "Attach receipt" row (docs/JOURNEYS.md J3b -> the typed door
    /// is a peer, so its entries can carry the paper too). One tap opens the
    /// camera/Photos choice; the OCR then offers pre-fills for blank fields
    /// only, never overwriting a typed value (hard rule 13).
    var attachReceiptRow: some View {
        Button {
            showAttachSource = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text("Attach receipt")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer(minLength: 8)
            }
            .padding(12)
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("confirmAttachReceiptRow")
        // RV.11: the source chooser is presented FROM THIS ROW, not from the
        // screen. Under iOS 26 a `confirmationDialog` renders as a popover
        // anchored to the view it is attached to; attached to the ScrollView -
        // where it lived until 2026-09-03 - the arrow pointed at the middle of
        // the form while the button the user had just tapped was at the bottom.
        // On iOS 18 the same modifier is a bottom action sheet and the anchor is
        // ignored, so this is correct on both and only observable on one.
        .receiptAttachSource(isPresented: $showAttachSource, title: "Attach receipt") { image in
            attachReceipt(image)
        }
    }

    /// One image in, one set of blank-fields-only suggestions out (the same
    /// `CapturePipeline` the scan door uses). Blank is decided from the form's
    /// own typed state via `ReceiptAttachMerge`; only blank fields are offered,
    /// each dimmed until confirmed. The picked photo is held for Save.
    func attachReceipt(_ image: UIImage) {
        guard let vehicle else { return }
        Task {
            let prefill = await CapturePipeline.process(
                image, source: .receipt,
                bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle.id))
            attachedPrefill = prefill
            guard let extraction = prefill.extraction else { return }
            let entry = form.blankDetectingEntry(vehicle: vehicle)
            let suggestions = ReceiptAttachMerge.suggestions(entry: entry, extraction: extraction)
            form.applyAttachedSuggestions(suggestions, extraction: extraction)
            // Attaching a photo is a real change, guarded like a typed edit.
            hasUnsavedChanges = true
        }
    }
}

// MARK: - PJ.2 the scanned save (one receipt photo, shared)

extension ManualFillUpView {
    /// The save's scan shape: the shared attachment id, the provenance, and the
    /// extraction record. `nil` prefill IS the typed path (hard rule 15): no
    /// attachment, `.manual`, no extraction record.
    func scannedSavePlan(derived: ManualFillUpMath.Derived) -> ScannedSavePlan {
        let saved = ScannedSaveValues(total: derived.total, volumeL: derived.volumeL,
                                      unitPrice: derived.unitPrice, currency: form.currency,
                                      fuelKind: form.fuelKind, date: form.date)
        // PJ.48: an attached receipt on the typed path. Provenance stays
        // `.manual` (the entry was typed); no QR anchor, so the OCR never fights
        // a typed value; the extraction records the attach.
        if let attach = attachedPrefill {
            return ScannedSavePlanner.plan(
                extraction: attach.extraction,
                cropRects: cropRects(from: attach.crops),
                qrAnchor: nil,
                declaredProvenance: .manual,
                hasPhoto: attach.sourceImage != nil,
                saved: saved)
        }
        return ScannedSavePlanner.plan(
            extraction: prefill?.extraction,
            cropRects: cropRects(from: prefill?.crops ?? [:]),
            qrAnchor: prefill?.qrAnchor,
            declaredProvenance: prefill?.provenance ?? .manual,
            hasPhoto: prefill?.sourceImage != nil,
            saved: saved)
    }

    /// The photo the save writes: the attached one on the typed path, else the
    /// scanned one. The two are mutually exclusive - an attach happens only
    /// where no scan prefill exists.
    var receiptSource: ConfirmPrefill? {
        attachedPrefill ?? prefill
    }

    /// The prefill's per-field crop evidence becomes the extraction record's
    /// crop rects (`FieldExtraction.cropRect`, image pixel space).
    func cropRects(from crops: [ManualFillUpMath.Field: CropEvidence]) -> [FieldRef: CGRect] {
        crops.reduce(into: [:]) { result, entry in
            result[entry.key.fieldRef] = entry.value.rect
        }
    }

    /// RV.149: the save's report half, called ONLY after the entry is on disk.
    /// A receipt photo the save could not keep is never a silent drop (hard
    /// rule 8) and never blocks the entry (hard rule 1); the shared message -
    /// the same sentence the expense save shows (PJ.28) - names the next step
    /// (hard rule 7, docs/ERRORS.md -> Confirm, RV.149). Fired on the success
    /// path only, so a failed save never claims it succeeded.
    func reportLostReceiptPhoto(_ outcome: ReceiptWriteOutcome,
                                toastCenter: AppToastCenter) {
        guard outcome.lostPhoto else { return }
        toastCenter.show(L10n.receiptNotSavedMessage)
    }
}

// MARK: - RV.149 the photo-write degrade contract (free, L1-testable)

/// The outcome of the one shared receipt-photo write a scanned save attempts.
/// `nothingToWrite` is the typed path; `lost` is a write that threw - the entry
/// still saves, without the photo, and the save reports it (docs/ERRORS.md ->
/// Confirm, the RV.149 row). Never a blocked save (hard rule 1), never a silent
/// drop (hard rule 8).
enum ReceiptWriteOutcome: Equatable {
    case nothingToWrite
    case wrote(AttachmentID)
    case lost(AttachmentID)

    /// The attachment ids the save references: the shared id when the photo
    /// landed, empty on the typed path and when the photo was lost.
    var sharedIDs: [AttachmentID] {
        if case .wrote(let id) = self { return [id] }
        return []
    }

    /// Whether the photo was lost and the user must be told.
    var lostPhoto: Bool {
        if case .lost = self { return true }
        return false
    }
}

/// Attempts the scanned save's one receipt-photo write and reports the outcome.
/// Free of the view - the source photo is passed in, never read from `@State` -
/// so the degrade contract is L1-testable. A write failure is logged here
/// (shape-only, hard rule 12) and surfaces as `.lost`, never as a throw that
/// blocks the entry (hard rule 1).
func attemptReceiptPhotoWrite(scanned: ScannedSavePlan,
                              source: ConfirmPrefill?,
                              repository: TankbookRepository) -> ReceiptWriteOutcome {
    guard let attachmentID = scanned.attachmentID else { return .nothingToWrite }
    do {
        try writeReceiptPhoto(id: attachmentID, source: source,
                              extraction: scanned.extraction,
                              repository: repository)
        return .wrote(attachmentID)
    } catch {
        AppLog.error(operation: "confirmManual.receiptPhotoSave", category: .ui, error: error)
        return .lost(attachmentID)
    }
}

/// Writes the receipt photo once: file bytes into the shared attachments
/// directory (the same pool `InvoiceAttachmentFiles` uses, docs/SYNC.md), one
/// `Attachment` row shared by the fill-up and every accepted expense, with the
/// inline thumbnail in the payload (P4.6) and - RV.48 - the parse's per-field
/// ASSIGNMENT (`extraction`), so the recognised page shows what the receipt
/// said, not line soup.
func writeReceiptPhoto(id: AttachmentID,
                       source: ConfirmPrefill?,
                       extraction: ExtractionMeta?,
                       repository: TankbookRepository) throws {
    guard let source, let sourceImage = source.sourceImage else { return }
    guard let jpeg = sourceImage.jpegData(compressionQuality: 0.8) else {
        throw ReceiptAttachmentError.notEncodable
    }
    let (sha256, relativePath) = try VehiclePhotoStore.save(jpeg, id: id)
    let thumbnail = (try? AttachmentRendition.thumbnailBase64(for: jpeg, kind: .photo)) ?? nil
    let ocrText = source.ocrLines.isEmpty ? nil : source.ocrLines.map(\.text).joined(separator: "\n")
    // The receipt's own printed date when the extraction read one, else the
    // fiscal QR's timestamp (docs/SCHEMA.md, Attachment.extractedTimestamp).
    let timestamp = (source.extraction?.date).flatMap { ConfirmDate.parse($0) }
        ?? source.qrAnchor?.date
    let now = Date()
    let attachment = Attachment(
        id: id, createdAt: now, updatedAt: now, deletedAt: nil,
        kind: .photo, file: LocalFileRef(sha256: sha256, relativePath: relativePath),
        extractedTimestamp: timestamp, ocrText: ocrText, thumbnailBase64: thumbnail,
        // A parse that assigned nothing stores no container at all, never an
        // empty one (RV.48).
        extractionMeta: extraction?.assignmentOnly)
    try repository.upsertAttachment(attachment)
}
