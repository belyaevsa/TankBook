import Foundation
import GRDB

// The Recently deleted store (P1.7), split out of Repository.swift to keep that
// file under the linter's file-length limit - same reason Repository+CarSelection
// and Repository+VehicleArchive exist.

extension TankbookRepository {
    /// All tombstoned entries across the entry tables, newest deletion first -
    /// the Recently deleted screen's data (hard rule 8: nothing lost silently;
    /// every tombstone lives here for the 30-day window). Each row knows what
    /// it was (the entry is intact), when it was deleted and how long it has
    /// left. `deletedOnDevice` is nil - the real device attribution arrives
    /// with sync (P4); the app target fakes it for fixtures.
    public func deletedEntries() throws -> [DeletedEntry] {
        try database.read { db in
            var result: [DeletedEntry] = []
            let predicate = Column("deletedAt") != nil

            let fills: [DeletedEntry] = try FillUpRow
                .filter(predicate).fetchAll(db)
                .compactMap { $0.fillUp.deletedAt != nil ? DeletedEntry(entry: $0.fillUp) : nil }
            result.append(contentsOf: fills)

            let charges: [DeletedEntry] = try ChargeSessionRow
                .filter(predicate).fetchAll(db)
                .compactMap { $0.chargeSession.deletedAt != nil ? DeletedEntry(entry: $0.chargeSession) : nil }
            result.append(contentsOf: charges)

            let serviceRows = try ServiceRecordRow.filter(predicate).fetchAll(db)
            let services: [DeletedEntry] = serviceRows
                .compactMap { $0.service.deletedAt != nil ? DeletedEntry(entry: $0.service) : nil }
            result.append(contentsOf: services)

            let expenses: [DeletedEntry] = try ExpenseRow
                .filter(predicate).fetchAll(db)
                .compactMap { $0.expense.deletedAt != nil ? DeletedEntry(entry: $0.expense) : nil }
            result.append(contentsOf: expenses)

            return result.sorted { ($0.deletedAt, $0.entry.date) > ($1.deletedAt, $1.entry.date) }
        }
    }

    /// All tombstoned reminders, newest deletion first - the Recently deleted
    /// screen lists reminders beside the entry list (PJ.7). A reminder is NOT
    /// an `Entry` (no `date`/`money`), so it cannot ride in `deletedEntries()`;
    /// it is a parallel list with the same 30-day window and the same Restore
    /// path (`restoreReminder`). Hard rule 8 - nothing lost silently - holds
    /// for reminders exactly as it does for entries: a deleted reminder is
    /// recoverable and reachable until the purge.
    public func deletedReminders() throws -> [DeletedReminder] {
        try database.read { db in
            try ReminderRow
                .filter(Column("deletedAt") != nil)
                .fetchAll(db)
                .compactMap { row -> DeletedReminder? in
                    guard row.reminder.deletedAt != nil else { return nil }
                    return DeletedReminder(reminder: row.reminder)
                }
                .sorted { $0.deletedAt > $1.deletedAt }
        }
    }

    /// Restores any tombstoned entry - the screen's Restore button (hard rule
    /// 8: restoring clears the tombstone and the entry re-enters the Log and
    /// the statistics, because stats are derived and the next recompute sees
    /// the live row again - docs/SCHEMA.md, Recalculation on edit). Returns
    /// true when a tombstone was found and restored.
    @discardableResult
    public func restoreEntry(id: UUID) throws -> Bool {
        try database.write { db in
            let stamp = Date().timeIntervalSinceReferenceDate
            for table in TankbookSchema.entryTables {
                try db.execute(sql: """
                    UPDATE \(table)
                    SET deletedAt = NULL, updatedAt = ?, syncState = 'dirty'
                    WHERE id = ? AND deletedAt IS NOT NULL
                    """, arguments: [stamp, id.uuidString])
                if db.changesCount > 0 { return true }
            }
            return false
        }
    }

    /// Permanently removes EVERY tombstone regardless of age - the Recently
    /// deleted screen's destructive "Delete all now" (system-confirmed, the one
    /// place red lives, hard rule 5). This is the same purge path as the
    /// scheduled one (same safety rule: a vehicle tombstone is kept while any
    /// of its rows are still live), just with no grace period. Idempotent.
    public func purgeAllTombstones() throws {
        try purgeTombstones(olderThan: Date())
    }
}
