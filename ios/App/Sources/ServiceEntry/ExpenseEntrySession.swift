import Foundation
import Observation
import TankbookCore

/// Carries the just-scanned expense pre-fill from the Capture flow into the
/// ExpenseEntry sheet (RV.62). Capture processes the frame and writes the
/// recognised total/currency/date here; ExpenseEntry reads it on load - the
/// same single in-memory hand-off `ServiceInvoiceSession` gives the Service
/// path (P3.1b). A pre-fill is default input the user edits (hard rule 13),
/// never a second screen, so nothing is persisted until the user saves.
///
/// Also carries the expense-category pre-selection from the ServiceEntry mode
/// row into the ExpenseEntry sheet (P3.2). Tapping "Parts" presets `.parts`,
/// tapping "Other" leaves the picker at its default - both are a default input
/// the user edits, never a locked choice. `pendingPrefill` is written only by
/// Capture; `pendingPreset` only by ServiceEntry; they never race.
@MainActor
@Observable
final class ExpenseEntrySession {
    var pendingPreset: ExpenseCategory?
    /// The scan's pre-fill, when ExpenseEntry is opening from an Expense-mode
    /// capture. Consumed (cleared) on load, exactly as `pendingPreset` is.
    var pendingPrefill: ExpensePrefill?
}
