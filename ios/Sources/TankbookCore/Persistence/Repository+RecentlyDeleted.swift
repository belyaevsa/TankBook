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
    ///
    /// RV.98: an entry whose tombstone stamp matches its (tombstoned)
    /// vehicle's stamp came down WITH the car and comes back WITH the car, so
    /// it is NOT a separate row - it belongs under the car's row in
    /// `deletedVehicles()`. A row the user deleted individually while the car
    /// was live keeps its own stamp and lists here exactly as before.
    public func deletedEntries() throws -> [DeletedEntry] {
        try database.read { db in
            let coTombstoneStamps = try tombstonedVehicleStamps(in: db)
            var result: [DeletedEntry] = []
            let predicate = Column("deletedAt") != nil

            let fills: [DeletedEntry] = try FillUpRow
                .filter(predicate).fetchAll(db)
                .compactMap { row in
                    guard row.fillUp.deletedAt != nil,
                          !isCoTombstoned(row.fillUp.vehicleId, row.fillUp.deletedAt, stamps: coTombstoneStamps) else { return nil }
                    return DeletedEntry(entry: row.fillUp)
                }
            result.append(contentsOf: fills)

            let charges: [DeletedEntry] = try ChargeSessionRow
                .filter(predicate).fetchAll(db)
                .compactMap { row in
                    guard row.chargeSession.deletedAt != nil,
                          !isCoTombstoned(row.chargeSession.vehicleId, row.chargeSession.deletedAt, stamps: coTombstoneStamps) else { return nil }
                    return DeletedEntry(entry: row.chargeSession)
                }
            result.append(contentsOf: charges)

            let serviceRows = try ServiceRecordRow.filter(predicate).fetchAll(db)
            let services: [DeletedEntry] = serviceRows.compactMap { row in
                guard row.service.deletedAt != nil,
                      !isCoTombstoned(row.service.vehicleId, row.service.deletedAt, stamps: coTombstoneStamps) else { return nil }
                return DeletedEntry(entry: row.service)
            }
            result.append(contentsOf: services)

            let expenses: [DeletedEntry] = try ExpenseRow
                .filter(predicate).fetchAll(db)
                .compactMap { row in
                    guard row.expense.deletedAt != nil,
                          !isCoTombstoned(row.expense.vehicleId, row.expense.deletedAt, stamps: coTombstoneStamps) else { return nil }
                    return DeletedEntry(entry: row.expense)
                }
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
    ///
    /// RV.98: the same co-tombstone rule as `deletedEntries()` - a reminder a
    /// car deletion swept up shares the vehicle's stamp and comes back with the
    /// car's Restore, so it is not a separate row with a Restore of its own
    /// that would strand it on a deleted vehicle.
    public func deletedReminders() throws -> [DeletedReminder] {
        try database.read { db in
            let coTombstoneStamps = try tombstonedVehicleStamps(in: db)
            return try ReminderRow
                .filter(Column("deletedAt") != nil)
                .fetchAll(db)
                .compactMap { row -> DeletedReminder? in
                    guard row.reminder.deletedAt != nil,
                          !isCoTombstoned(row.reminder.vehicleId, row.reminder.deletedAt, stamps: coTombstoneStamps) else { return nil }
                    return DeletedReminder(reminder: row.reminder)
                }
                .sorted { $0.deletedAt > $1.deletedAt }
        }
    }

    /// All tombstoned vehicles, newest deletion first - the Recently deleted
    /// screen's car rows (RV.98). Deleting a car tombstones it and every
    /// vehicle-scoped row at one stamp, so the whole group is one row here:
    /// `entriesCount` says how many entries went down with it and its Restore
    /// (`restoreVehicle`) brings the car and exactly those entries back.
    /// Nothing queries the vehicle's own tombstone is the defect this fixes -
    /// a deleted car was invisible and unrestorable by any surface (hard rule 8).
    public func deletedVehicles() throws -> [DeletedVehicle] {
        try database.read { db in
            let rows = try VehicleRow.filter(Column("deletedAt") != nil).fetchAll(db)
            var result: [DeletedVehicle] = []
            for row in rows {
                let vehicle = row.vehicle
                guard let stamp = vehicle.deletedAt else { continue }
                let interval = stamp.timeIntervalSinceReferenceDate
                var covered = 0
                for table in TankbookSchema.entryTables {
                    let count = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM \(table)
                        WHERE vehicleId = ? AND deletedAt = ?
                        """, arguments: [vehicle.id.uuidString, interval]) ?? 0
                    covered += count
                }
                result.append(DeletedVehicle(vehicle: vehicle, entriesCount: covered))
            }
            return result.sorted { $0.deletedAt > $1.deletedAt }
        }
    }

    /// vehicleId -> tombstone stamp of every TOMBSTONED vehicle. An entry or
    /// reminder whose own stamp equals its vehicle's came down WITH the car
    /// (`softDeleteVehicle` writes one stamp across the vehicle and every
    /// vehicle-scoped row) and belongs under the car's Recently deleted row,
    /// not beside it with a Restore of its own (RV.98 decision 3). The stamps
    /// are the raw values `restoreVehicle` compares against - exact equality is
    /// the group-restore contract, not an approximation.
    private func tombstonedVehicleStamps(in db: Database) throws -> [UUID: Date] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, deletedAt FROM vehicle WHERE deletedAt IS NOT NULL
            """)
        var result: [UUID: Date] = [:]
        for row in rows {
            guard let id = UUID(uuidString: row["id"] as String),
                  let interval = row["deletedAt"] as Double? else { continue }
            result[id] = Date(timeIntervalSinceReferenceDate: interval)
        }
        return result
    }

    /// Whether a tombstoned row shares its (tombstoned) vehicle's stamp - i.e.
    /// was swept up by the car's deletion rather than deleted on its own.
    private func isCoTombstoned(_ vehicleId: UUID, _ deletedAt: Date?,
                                stamps: [UUID: Date]) -> Bool {
        guard let deletedAt,
              let vehicleStamp = stamps[vehicleId] else { return false }
        return deletedAt == vehicleStamp
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
