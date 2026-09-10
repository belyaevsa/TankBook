import UIKit
import Foundation
import Observation
import TankbookCore

/// The receipt photo and recognition evidence of one Expense-mode capture
/// (PJ.28). Capture writes it to `ExpenseEntrySession.pendingCapture` next to
/// the value pre-fill; the Expense sheet consumes it on load and persists the
/// receipt when the user saves - so a scanned expense keeps the photograph it
/// was read from, exactly as a fill-up's scanned save does. The image lives
/// here (app target), never in the core `ExpensePrefill`, whose total /
/// currency / date members stay the only channel into the form's fields.
struct ExpenseScanCapture {
    let image: UIImage
    /// The recognition result the capture read off the receipt. Only its
    /// total / currency / date cross into the stored extraction record
    /// (`ExpenseReceiptWrite`); liters and fuel kind never ride along (RV.62).
    let extraction: FuelExtraction
    /// The raw OCR lines, stored on the attachment as `ocrText` for re-parsing
    /// after a parser upgrade (docs/SCHEMA.md, Attachment.ocrText).
    let ocrLines: [OCRLine]
}

/// Carries the just-scanned expense pre-fill from the Capture flow into the
/// ExpenseEntry sheet (RV.62). Capture processes the frame and writes the
/// recognised total/currency/date here; ExpenseEntry reads it on load - the
/// same single in-memory hand-off `ServiceInvoiceSession` gives the Service
/// path (P3.1b). A pre-fill is default input the user edits (hard rule 13),
/// never a second screen, so nothing is persisted until the user saves.
///
/// PJ.28: the photograph itself travels the same one-shot channel
/// (`pendingCapture`) so a scanned expense saves with its receipt attached and
/// a second open of the form never re-attaches a stale photo.
///
/// Also carries the expense-category pre-selection into the ExpenseEntry sheet
/// (P3.2, extended RV.200). Two writers, one field: ServiceEntry's mode row
/// presets the category it was tapped from (tapping "Parts" presets `.parts`,
/// "Other" leaves the default), and an Expense-mode capture writes the kind its
/// own scan suggested (`ExpenseCategoryInference`). Both are a default input
/// the user edits, never a locked choice (hard rule 13). `pendingPrefill` is
/// written only by Capture, which writes `pendingPreset` in the same turn; a
/// plain ServiceEntry preset carries no prefill. The two values are consumed
/// together on load, so the scan's category is applied before its amount.
@MainActor
@Observable
final class ExpenseEntrySession {
    /// The category the form opens on, when something suggested one: nil leaves
    /// the form's own `.accessory` default, which is the "no kind recognised"
    /// answer (RV.200) - never an error and never a guess.
    var pendingPreset: ExpenseCategory?
    /// The scan's pre-fill, when ExpenseEntry is opening from an Expense-mode
    /// capture. Consumed (cleared) on load, exactly as `pendingPreset` is.
    var pendingPrefill: ExpensePrefill?
    /// The scan's photograph, when ExpenseEntry is opening from an Expense-mode
    /// capture. Written next to `pendingPrefill` and consumed with it on load,
    /// so the photo is attached to the save that follows this open - and to no
    /// later one (the row's vacuous trap: a second open must not re-attach it).
    var pendingCapture: ExpenseScanCapture?

    /// PJ.28: consumes (clears) the staged capture. `nil` when no scan is open
    /// or the capture was already consumed - the one-shot discipline the value
    /// pre-fill already follows, applied to the photograph.
    func consumePendingCapture() -> ExpenseScanCapture? {
        defer { pendingCapture = nil }
        return pendingCapture
    }
}
