import Foundation

// The vehicle archive/restore store (P1.12, J13), kept in its own file so
// Repository.swift stays under the linter's file-length limit - same reason
// Repository+CarSelection.swift exists. Archive and unarchive are the two
// writes that keep `archived` and `archivedAt` consistent: both bump
// `updatedAt` and mark the row dirty so the sync queue sees the change.

extension TankbookRepository {
    /// Archives a vehicle (J13): history kept, out of active stats. Sets the
    /// `archived` flag and stamps `archivedAt` at the same instant so the two
    /// can never disagree and the Car switcher can honestly render "sold <when>"
    /// (docs/SCHEMA.md, Vehicle -> archivedAt).
    public func archiveVehicle(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            let stamp = date.timeIntervalSinceReferenceDate
            try db.execute(sql: """
                UPDATE \(TankbookSchema.vehicle)
                SET archived = 1, archivedAt = ?, updatedAt = ?, syncState = 'dirty', syncScn = NULL
                WHERE id = ? AND deletedAt IS NULL
                """, arguments: [stamp, stamp, id.uuidString])
        }
    }

    /// Unarchives a vehicle: back in active stats, the archive stamp cleared.
    public func unarchiveVehicle(id: UUID) throws {
        try database.write { db in
            let stamp = Date().timeIntervalSinceReferenceDate
            try db.execute(sql: """
                UPDATE \(TankbookSchema.vehicle)
                SET archived = 0, archivedAt = NULL, updatedAt = ?, syncState = 'dirty', syncScn = NULL
                WHERE id = ? AND deletedAt IS NULL
                """, arguments: [stamp, id.uuidString])
        }
    }
}
