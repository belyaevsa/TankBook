import Foundation
import TankbookCore

// RV.243: the repository half of the Expense sheet's save, split out of
// `ExpenseEntryView.swift` (which sits near the linter's file-length ceiling)
// and injected with the repository so the L1 tests drive the EXACT write -
// receipt photo included - and read the stored row back. The photo write runs
// from whatever capture the sheet holds at save, never from the read's state: a
// read still in flight must not cost the user the photograph (hard rule 8).

extension ExpenseEntryView {
    /// Persists the expense the save asked for, receipt photo first. The photo
    /// is written from `scan` - the capture staged when the scan started
    /// (`ExpenseEntrySession.stageScan`), so a save that beats the read still
    /// keeps it. A write failure degrades to no photo rather than throwing
    /// (RV.149's contract): the expense still saves, and the caller reports the
    /// loss after the row is on disk. Returns the stored row and whether the
    /// photo was lost.
    @MainActor
    static func writeExpense(
        form: ExpenseEntryFormState, vehicle: Vehicle, amount: Decimal,
        scan: ExpenseScanCapture?, repository: TankbookRepository
    ) throws -> (expense: Expense, photoWriteFailed: Bool) {
        var attachmentIDs: [AttachmentID] = []
        var photoWriteFailed = false
        if let scan {
            do {
                attachmentIDs = [try ExpenseReceiptWrite.write(scan: scan,
                                                               repository: repository)]
            } catch {
                AppLog.error(operation: "expenseEntry.receiptPhotoSave",
                             category: .ui, error: error)
                photoWriteFailed = true
            }
        }
        let now = Date()
        var expense = storedExpense(
            form: form, vehicle: vehicle, amount: amount,
            attachments: attachmentIDs,
            provenance: scan != nil ? .receiptScan : .manual, now: now)
        let existing = try repository.liveEntries(forVehicle: vehicle.id)
        let validations = TimelineValidator.validate(entries: existing + [expense],
                                                     vehicle: vehicle)
        expense.conflict = validations.first { $0.entryID == expense.id }?.conflict ?? .none
        try repository.upsertExpense(expense)
        return (expense, photoWriteFailed)
    }
}
