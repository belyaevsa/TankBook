import UIKit
import TankbookCore

// MARK: - PJ.28 the scanned Expense save's receipt photo
//
// The Expense sheet's Save calls `write` when a scan carried a photograph; the
// typed path never does (hard rule 15 - a photo is a head start, never a
// requirement). Kept out of `ExpenseEntryView.swift` so that file stays within
// the lint budget and the write is a peer seam to the Confirm sheet's
// (`ManualFillUpReceiptSave.swift`), the shape this one mirrors: JPEG bytes
// into the shared attachments pool, one `Attachment` row with the inline
// thumbnail, the OCR text, the receipt's own printed date as
// `extractedTimestamp` (docs/SCHEMA.md -> PRIORITY) and the parse's value
// assignment on the attachment (RV.48). It reuses `ReceiptAttachmentWriter` -
// the one photo-writing path every attach surface shares (docs/SYNC.md) - so
// there is not a second, subtly different way to persist a receipt.

/// The receipt half of an Expense save. A scanned Expense carries its photo
/// here; a manual one never reaches this type. A failed write throws - the
/// caller still saves the expense without the photo and tells the user
/// (docs/ERRORS.md -> Service & expenses) - never a silent drop (hard rule 8)
/// and never a blocked save.
enum ExpenseReceiptWrite {
    /// Persists the scanned expense's receipt photo and returns the id the
    /// `Expense` must carry in `attachments`. Throws
    /// `ReceiptAttachmentError.notEncodable` when the image cannot be encoded
    /// or a storage error when it cannot be written.
    static func write(scan: ExpenseScanCapture,
                      repository: TankbookRepository) throws -> AttachmentID {
        let id = UUID.v7()
        // RV.62's boundary, applied to the stored assignment too: a shop
        // receipt is not a fuel receipt, so only total / currency / date are
        // recorded on the attachment - liters, unit price and fuel kind that
        // the shared fill-up recognizer may resolve never ride into an
        // Expense's extraction record.
        let expenseFields = FuelExtraction(total: scan.extraction.total,
                                           currency: scan.extraction.currency,
                                           date: scan.extraction.date)
        let attachment = try ReceiptAttachmentWriter.write(
            id: id, image: scan.image,
            ocrLines: scan.ocrLines, extraction: expenseFields)
        try repository.upsertAttachment(attachment)
        return id
    }
}
