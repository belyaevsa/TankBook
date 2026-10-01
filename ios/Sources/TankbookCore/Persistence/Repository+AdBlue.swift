import Foundation
import GRDB

// MARK: - AdBlueFill

extension TankbookRepository {
    public func upsertAdBlueFill(_ fill: AdBlueFill, syncState: SyncState = .dirty) throws {
        try database.write { db in
            var row = AdBlueFillRow(adBlueFill: fill, syncState: syncState)
            row.syncScn = try preservingScn(syncState, table: TankbookSchema.adBlueFill, id: fill.id, in: db)
            try row.save(db)
        }
    }

    public func softDeleteAdBlueFill(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.adBlueFill, id: id, at: date.timeIntervalSinceReferenceDate, in: db)
        }
    }

    public func restoreAdBlueFill(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.adBlueFill, id: id, at: Date().timeIntervalSinceReferenceDate, in: db)
        }
    }

    public func liveAdBlueFills(forVehicle vehicleId: UUID) throws -> [AdBlueFill] {
        try database.read { db in
            try fetchLive(AdBlueFillRow.self, vehicleId: vehicleId, in: db).map(\.adBlueFill)
        }
    }
}
