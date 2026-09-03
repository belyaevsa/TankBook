import Foundation
import GRDB

// MARK: - RV.38 the inbox's read (docs/JOURNEYS.md F4, amended)
//
// The inbox resolves against the entry the user saved, so it needs one fill-up
// by id - including a tombstoned row (a later sync tombstone must not make a
// pending item unreadable). Lives in its own file so `Repository.swift` stays
// under its 700-line lint budget.

extension TankbookRepository {
    /// One fill-up by id, including a tombstoned row. `nil` when the row never
    /// existed.
    public func fillUp(id: UUID) throws -> FillUp? {
        try database.read { db in
            try FillUpRow.fetchOne(db, key: id.uuidString)?.fillUp
        }
    }
}
