import Foundation
import TankbookCore

/// "Add expense from this receipt" (PJ.41): what Edit entry hands the Expense
/// sheet when a second purchase on an already-logged receipt is added later.
/// The expense shares the source entry's receipt photo by reference - the same
/// `AttachmentID`s, never a copy (docs/SCHEMA.md, `attachments`) - and its
/// `purchaseGroupId`, so the Log renders the two as one purchase.
struct ExpenseReceiptLink: Equatable {
    /// The entry the receipt already belongs to.
    let sourceEntryID: UUID
    let vehicleID: UUID
    /// The date the expense form opens on: the purchase happened with the source.
    let date: Date
    /// The source's receipt photos, referenced as-is.
    let attachments: [AttachmentID]
    /// The source's group, when it already has one. Nil means the save creates
    /// a group and writes it to the source as well - only on save, so a
    /// cancelled expense leaves the source untouched.
    let purchaseGroupId: UUID?

    init(source: any Entry) {
        sourceEntryID = source.id
        vehicleID = source.vehicleId
        date = source.date
        attachments = source.attachments
        purchaseGroupId = source.purchaseGroupId
    }

    /// The group the saved expense joins: the source's, or a new one.
    func groupForSave(newGroup: () -> UUID = { UUID.v7() }) -> UUID {
        purchaseGroupId ?? newGroup()
    }
}

extension ExpenseReceiptLink {
    /// Writes `group` to the source entry when it has none yet - the other half
    /// of the save (the expense carries the group already). A source that is
    /// gone or already grouped is left as it is. Returns whether it wrote.
    @MainActor
    @discardableResult
    static func joinSource(_ link: ExpenseReceiptLink, group: UUID,
                           repository: TankbookRepository, now: Date = Date()) throws -> Bool {
        guard link.purchaseGroupId == nil else { return false }
        let entries = try repository.liveEntries(forVehicle: link.vehicleID)
        guard let source = entries.first(where: { $0.id == link.sourceEntryID }),
              source.purchaseGroupId == nil else { return false }
        switch source {
        case var fill as FillUp:
            fill.purchaseGroupId = group
            fill.updatedAt = now
            try repository.upsertFillUp(fill)
        case var charge as ChargeSession:
            charge.purchaseGroupId = group
            charge.updatedAt = now
            try repository.upsertChargeSession(charge)
        case var service as ServiceRecord:
            service.purchaseGroupId = group
            service.updatedAt = now
            try repository.upsertServiceRecord(service)
        case var expense as Expense:
            expense.purchaseGroupId = group
            expense.updatedAt = now
            try repository.upsertExpense(expense)
        default:
            return false
        }
        return true
    }
}
