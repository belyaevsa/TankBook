import Foundation
import GRDB

/// The derived flagged-entry count behind Settings' "N entries need a look"
/// (docs/SYNC.md -> "The count is derived, never stored"). It is the number of
/// LIVE records carrying a `ConflictState` across every entry table, recomputed
/// on every read exactly like any other statistic (hard rule 2's principle). A
/// stored counter would drift out of agreement with the per-entry badges, and
/// then two surfaces disagree about the same data - which is precisely the bug
/// this recompute prevents.
extension TankbookRepository {
    public func flaggedEntryCount() throws -> Int {
        try database.read { db in
            var count = 0
            for table in TankbookSchema.entryTables {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT conflict FROM \(table) WHERE deletedAt IS NULL
                    """)
                for row in rows {
                    guard let raw = row["conflict"] as String?,
                          let data = raw.data(using: .utf8),
                          let conflict = try? JSONDecoder().decode(ConflictState.self, from: data) else {
                        continue
                    }
                    if conflict != .none { count += 1 }
                }
            }
            return count
        }
    }

    /// The number of LIVE entry rows in the `rejected` sync state - the count
    /// behind Settings' "N entries could not sync" (docs/SYNC.md S7's 422
    /// sibling, RV.284). Derived at read time from the sync bookkeeping, never
    /// stored, exactly like `flaggedEntryCount` (hard rule 2's principle).
    public func rejectedEntryCount() throws -> Int {
        try database.read { db in
            var count = 0
            for table in TankbookSchema.entryTables {
                count += try Int.fetchOne(db, sql: """
                    SELECT count(*) FROM \(table) WHERE syncState = 'rejected' AND deletedAt IS NULL
                    """) ?? 0
            }
            return count
        }
    }

    /// The ids of the live entry rows in the `rejected` sync state - the badge
    /// on the entry row (RV.284). The Home log card renders a "not synced"
    /// badge for a member, tapping through to edit (the next step).
    public func rejectedEntryIDs() throws -> Set<UUID> {
        try database.read { db in
            var ids = Set<UUID>()
            for table in TankbookSchema.entryTables {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id FROM \(table) WHERE syncState = 'rejected' AND deletedAt IS NULL
                    """)
                for row in rows {
                    guard let id = UUID(uuidString: row["id"] as String) else { continue }
                    ids.insert(id)
                }
            }
            return ids
        }
    }
}
