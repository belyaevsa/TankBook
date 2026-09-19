import Foundation
import GRDB

/// S5: a car this device deleted came back archived because entries from
/// another device still referenced it. The notice is what the Garage/Home card
/// renders until the user answers it (docs/SYNC.md S5; docs/SCHEMA.md -> The S5
/// return notice).
public struct VehicleReturnNotice: Equatable, Sendable {
    public let vehicleId: UUID
    /// How many arriving entries brought the car back - one per pulled entry.
    public let entryCount: Int
    public let returnedAt: Date

    public init(vehicleId: UUID, entryCount: Int, returnedAt: Date) {
        self.vehicleId = vehicleId
        self.entryCount = entryCount
        self.returnedAt = returnedAt
    }
}

extension TankbookRepository {
    /// Every unanswered return notice whose car is still on the device (live -
    /// a car tombstoned again by the user has nothing left to answer).
    public func vehicleReturnNotices() throws -> [VehicleReturnNotice] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT n.vehicleId, n.entryCount, n.returnedAt
                FROM \(TankbookSchema.vehicleReturn) n
                JOIN \(TankbookSchema.vehicle) v ON v.id = n.vehicleId
                WHERE v.deletedAt IS NULL
                ORDER BY n.returnedAt
                """)
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["vehicleId"] as String) else { return nil }
                return VehicleReturnNotice(
                    vehicleId: id, entryCount: row["entryCount"] as Int,
                    returnedAt: Date(timeIntervalSinceReferenceDate: row["returnedAt"] as Double))
            }
        }
    }

    /// "Delete again": the car goes back where the user put it - tombstoned with
    /// its rows, dirty so the tombstone pushes (the arriving entry is among
    /// them: it lives in Recently deleted for the undo window, nothing is lost
    /// silently). The notice is consumed.
    public func deleteReturnedVehicleAgain(id: UUID) throws {
        try softDeleteVehicle(id: id)
        try clearVehicleReturnNotice(id: id)
    }

    /// "Keep": the car stays archived with its new entries; only the notice
    /// goes.
    public func keepReturnedVehicle(id: UUID) throws {
        try clearVehicleReturnNotice(id: id)
    }

    private func clearVehicleReturnNotice(id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM \(TankbookSchema.vehicleReturn) WHERE vehicleId = ?",
                           arguments: [id.uuidString])
        }
    }

    /// Records one arriving entry against the car's notice - a new notice at
    /// count 1, or one more on the notice already waiting. Called inside the
    /// resurrect write so a notice can never exist without its resurrection.
    func recordVehicleReturn(vehicleId: UUID, at stamp: TimeInterval, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO \(TankbookSchema.vehicleReturn) (vehicleId, entryCount, returnedAt)
            VALUES (?, 1, ?)
            ON CONFLICT(vehicleId) DO UPDATE SET entryCount = entryCount + 1, returnedAt = excluded.returnedAt
            """, arguments: [vehicleId.uuidString, stamp])
    }
}
