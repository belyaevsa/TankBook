import SwiftUI
import UIKit
import TankbookCore

// MARK: - RV.37 the delete/replace surfaces

// The viewer's two mutating surfaces, split out of `AttachmentViewerView.swift`
// to keep that file under the linter's file-length limit. Delete tombstones the
// attachment and unlinks it from the entry (system-confirmed - the one place red
// lives). Replace writes a NEW attachment plus a tombstone for the old one, then
// asks whether to re-read and update the entry; "Leave it as it is" is the
// default, and an accepted re-read fills blank fields only (hard rule 13).

extension AttachmentViewerView {

    /// The attachment the entry links right now - the one the viewer opened, or
    /// the newest replacement. "Use a different receipt" replaces THIS one, so a
    /// second replace never re-tombstones the already-tombstoned original.
    private var effectiveAttachmentID: AttachmentID { currentID ?? attachment.id }

    /// The bottom bar: Replace (the peer door - camera/Photos, reusing
    /// `receiptAttachSource`) and Delete. Both are always offered - a receipt
    /// the viewer cannot download is still replaceable and deletable (hard rule
    /// 1). Delete's red lives in the system confirm, never on the button
    /// (docs/ERRORS.md -> Edit entry).
    var actionBar: some View {
        VStack(spacing: 10) {
            if replaceFailed {
                replaceFailedWarn
            }
            if replaceProcessing {
                ProgressView()
                    .tint(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("attachmentViewerReplacing")
            } else {
                HStack(spacing: 24) {
                    Button("Replace photo") { showReplaceSource = true }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("attachmentViewerReplaceButton")
                    Spacer()
                    Button("Delete") { showDeleteConfirm = true }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("attachmentViewerDeleteButton")
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.vertical, 14)
        .background(Theme.Palette.midnight)
    }

    /// The failed-replace warn row (docs/ERRORS.md -> Edit entry): the entry is
    /// unchanged and the next step is named - try again. Amber is attention,
    /// never a block (hard rule 5).
    var replaceFailedWarn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't replace the photo – the entry is unchanged.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try again") { showReplaceSource = true }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
        }
        .padding(12)
        .background(Theme.Palette.dash.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachmentViewerReplaceFailed")
    }

    /// Delete: tombstone + unlink, in one write transaction in the repository.
    /// The attachment is a synced record with the 30-day tombstone exactly like
    /// any other entity - not a file quietly unlinked (hard rule 8). The blob is
    /// left alone (reclamation is out of scope).
    func performDelete() {
        do {
            let repository = try AppStore.repository()
            try repository.deleteAttachment(id: effectiveAttachmentID, from: entry)
            AppLog.info(operation: "attachmentViewer.delete", category: .ui, outcome: "deleted")
            onAttachmentChanged(nil)
            dismiss()
        } catch {
            AppLog.error(operation: "attachmentViewer.delete", category: .ui, error: error)
        }
    }

    /// Replace: one image in. The OCR runs through the same `CapturePipeline` the
    /// scan and attach doors use; the new attachment is written (photo + OCR +
    /// extraction), the entry relinked and the old attachment tombstoned - all in
    /// one repository write. The extraction is held for the ask: nothing touches
    /// the entry's field values until the user accepts, and even then only blank
    /// fields (hard rule 13).
    func handleReplace(_ image: UIImage) {
        replaceFailed = false
        replaceProcessing = true
        Task {
            let prefill = await CapturePipeline.process(image, source: .receipt)
            let extraction = prefill.extraction ?? FuelExtraction()
            do {
                let repository = try AppStore.repository()
                let newAttachment = try ReceiptAttachmentWriter.write(
                    id: UUID.v7(), image: image,
                    ocrLines: prefill.ocrLines, extraction: extraction)
                try repository.replaceAttachment(oldID: effectiveAttachmentID,
                                                 with: newAttachment, in: entry)
                currentID = newAttachment.id
                replaceExtraction = extraction
                replaceProcessing = false
                // The re-read ask is a fill-up concern only: a fuel extraction
                // has nothing to offer a charge, service record or expense, so
                // those swap the photo without an ask (never a dead option).
                if entry is FillUp {
                    showReplaceAsk = true
                } else {
                    onAttachmentChanged(nil)
                    dismiss()
                }
            } catch {
                replaceProcessing = false
                replaceFailed = true
                AppLog.error(operation: "attachmentViewer.replace", category: .ui, error: error)
            }
        }
    }
}
