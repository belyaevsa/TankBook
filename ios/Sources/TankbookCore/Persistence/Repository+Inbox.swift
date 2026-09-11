import Foundation
import GRDB

// MARK: - RV.38 the inbox's read (docs/JOURNEYS.md F4, amended); RV.201 the
// read generalised over entry kind.
//
// The inbox resolves against the entry the user saved, so it needs one entry
// by id - including a tombstoned row (a later sync tombstone must not make a
// pending item unreadable). The item's recognition kind names which entity to
// fetch, so `entry(id:kind:)` is the single lookup the resolution uses. Lives
// in its own file so `Repository.swift` stays under its 700-line lint budget.

extension TankbookRepository {
    /// One fill-up by id, including a tombstoned row. `nil` when the row never
    /// existed.
    public func fillUp(id: UUID) throws -> FillUp? {
        try database.read { db in
            try FillUpRow.fetchOne(db, key: id.uuidString)?.fillUp
        }
    }

    /// One service record by id with its line items attached. `nil` when the
    /// row never existed.
    public func serviceRecord(id: UUID) throws -> ServiceRecord? {
        try database.read { db in
            guard let row = try ServiceRecordRow.fetchOne(db, key: id.uuidString) else { return nil }
            return try attachServiceItems([row], in: db).first
        }
    }

    /// One expense by id. `nil` when the row never existed.
    public func expense(id: UUID) throws -> Expense? {
        try database.read { db in
            try ExpenseRow.fetchOne(db, key: id.uuidString)?.expense
        }
    }
}
