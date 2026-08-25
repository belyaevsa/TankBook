import Foundation
import GRDB

/// Parts-shelf install linking (docs/SCHEMA.md -> Expense.installedInServiceId +
/// ServiceRecord.usedParts). Every write here commits BOTH halves of a link in
/// one transaction - a half-written link is a part that is neither on the shelf
/// nor in the service.
extension TankbookRepository {

    /// Saves a service AND writes the other half of each part-install link in
    /// the same transaction. The record's `usedParts` are the linked parts; the
    /// linked expenses' `installedInServiceId` names the record. Cost never
    /// moves: linking is provenance, not a price (docs/PHASES.md, P3 exit gate).
    public func upsertServiceRecord(_ service: ServiceRecord, linkedParts expenses: [Expense],
                                    syncState: SyncState = .dirty) throws {
        try database.write { db in
            try ServiceRecordRow(service: service, syncState: syncState).save(db)
            // Items are an ordered value list: replace wholesale.
            try db.execute(sql: "DELETE FROM \(TankbookSchema.serviceItem) WHERE serviceRecordId = ?",
                           arguments: [service.id.uuidString])
            for (position, item) in service.items.enumerated() {
                try ServiceItemRow(serviceRecordId: service.id, position: position, item: item).insert(db)
            }
            for expense in expenses {
                try ExpenseRow(expense: expense, syncState: syncState).save(db)
            }
        }
    }

    /// Writes both halves of a part-install link in one transaction. Used to
    /// link and unlink a part to/from an ALREADY-SAVED service: the caller
    /// applies `PartsShelf.link`/`unlink` to the in-memory values and hands both
    /// here, so `installedInServiceId` and `usedParts` commit together.
    public func saveLink(expense: Expense, service: ServiceRecord) throws {
        try database.write { db in
            try ExpenseRow(expense: expense, syncState: .dirty).save(db)
            try ServiceRecordRow(service: service, syncState: .dirty).save(db)
        }
    }

    /// The parts currently on the shelf for a vehicle: `.parts` expenses not
    /// installed in any live service (docs/JOURNEYS.md J7b). Derived, never
    /// stored - `PartsShelf.onShelf` is the single rule.
    public func partsOnShelf(forVehicle vehicleId: UUID) throws -> [Expense] {
        let expenses = try liveExpenses(forVehicle: vehicleId)
        let liveServiceIds = Set(try liveServiceRecords(forVehicle: vehicleId).map(\.id))
        return PartsShelf.onShelf(expenses: expenses, liveServiceIds: liveServiceIds)
    }
}
