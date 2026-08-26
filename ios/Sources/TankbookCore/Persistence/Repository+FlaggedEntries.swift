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
}
