import SwiftUI
import TankbookCore

/// PJ.41: "Add expense from this receipt" - one receipt, a second purchase on
/// it logged later (the car wash on the fuel receipt). Shown under the receipt
/// card only when the entry has a photo; it opens the Expense sheet on the same
/// date and car, sharing the photo and the purchase group (`ExpenseReceiptLink`).
struct AddExpenseFromReceiptButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                Text("Add expense from this receipt")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.ink)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .formCard()
        .accessibilityIdentifier("editEntryAddExpenseFromReceipt")
    }
}

extension EditEntryView {
    /// Stages the link and opens the Expense sheet over this screen.
    func openExpenseFromReceipt() {
        guard let currentEntry, !currentEntry.attachments.isEmpty else { return }
        expenseSession.pendingReceiptLink = ExpenseReceiptLink(source: currentEntry)
        expenseSheet = .expenseEntry
    }

    /// The Expense sheet closed. A saved expense may have given this entry a
    /// purchase group, so the in-memory copy takes the stored group - a later
    /// Save here must not write the stale copy back and erase it. A sheet left
    /// without a save drops the link, so no later expense inherits it.
    func expenseSheetClosed() async {
        expenseSession.pendingReceiptLink = nil
        guard let vehicle, let id = currentEntry?.id else { return }
        do {
            let repository = try AppStore.repository()
            let stored = try repository.liveEntries(forVehicle: vehicle.id).first { $0.id == id }
            guard let group = stored?.purchaseGroupId else { return }
            if var copy = fillUp { copy.purchaseGroupId = group; fillUp = copy }
            if var copy = charge { copy.purchaseGroupId = group; charge = copy }
            if var copy = service { copy.purchaseGroupId = group; service = copy }
            if var copy = expense { copy.purchaseGroupId = group; expense = copy }
        } catch {
            AppLog.error(operation: "editEntry.reloadPurchaseGroup", category: .ui, error: error)
        }
    }
}

#if DEBUG
extension EditEntryView {
    /// `-openExpenseFromReceipt`: taps "Add expense from this receipt" after
    /// load, so `simctl` (which cannot tap) can screenshot the sheet it opens.
    func openExpenseFromReceiptIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-openExpenseFromReceipt") else { return }
        openExpenseFromReceipt()
    }
}
#endif
