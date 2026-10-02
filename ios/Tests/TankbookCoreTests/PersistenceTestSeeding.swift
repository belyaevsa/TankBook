import Foundation
@testable import TankbookCore

/// Upserts a vehicle into a database held at an older schema: the columns a later
/// migration adds are added for the write and dropped again, so the table is
/// the older schema with a row in it - the forward-seeding rule the raw fillUp
/// seeds above follow, for a record whose encoder grew a later column.
func seedVehicleAtOlderSchema(_ vehicle: Vehicle, syncState: SyncState = .dirty,
                                      repo: TankbookRepository, database: TankbookDatabase) throws {
    try database.write { db in try db.execute(sql: "ALTER TABLE vehicle ADD COLUMN homeCity TEXT") }
    try repo.upsertVehicle(vehicle, syncState: syncState)
    try database.write { db in try db.execute(sql: "ALTER TABLE vehicle DROP COLUMN homeCity") }
}
