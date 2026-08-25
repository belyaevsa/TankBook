import Foundation
import Observation
import TankbookCore

/// Carries the expense-category pre-selection from the ServiceEntry mode row
/// into the ExpenseEntry sheet (P3.2). Tapping "Parts" presets `.parts`, tapping
/// "Other" leaves the picker at its default - both are a default input the user
/// edits (hard rule 13), never a locked choice. Mirrors `ServiceInvoiceSession`.
@MainActor
@Observable
final class ExpenseEntrySession {
    var pendingPreset: ExpenseCategory?
}
