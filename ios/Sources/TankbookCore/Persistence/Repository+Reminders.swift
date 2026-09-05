import Foundation
import GRDB

// MARK: - Reminder across vehicles

extension TankbookRepository {
    /// Live reminders across every ACTIVE vehicle - the merged "all cars" list
    /// (RV.75, design/screens/RemindersAll.dc.html, docs/SCREENMAP.md ->
    /// "Reminders across cars"). This is the ONE query the merged screen uses,
    /// so a list that claims to show every car cannot silently fall back to one
    /// vehicle's rows.
    ///
    /// What it excludes, and why:
    /// - **Tombstoned rows** (`deletedAt != nil`), exactly as the per-car query
    ///   does - a deleted reminder is in the 30-day undo window, not on any
    ///   list (hard rule 8).
    /// - **Archived cars' rows.** This is a decision, recorded here because it
    ///   is load-bearing: the merged list answers "what needs me", and an
    ///   archived car is a sold car - out of active stats, never the default
    ///   selection, with its monthly summary cancelled on archive (J13,
    ///   `VehicleSelection.resolve`, `VehicleDetailView.toggleArchive`). A sold
    ///   car's pending oil change is history, not a task for the coming
    ///   weekend; surfacing it here would compete with live cars' work for the
    ///   user's attention. Its rows are not lost: they stay on the per-car
    ///   screen (`liveReminders(forVehicle:)` is unchanged) and return to this
    ///   list the moment the car is unarchived - the exclusion is a read-time
    ///   derivation, never a stored state.
    ///
    /// A soft-deleted vehicle cannot leak rows here: `softDeleteVehicle`
    /// tombstones every vehicle-scoped table at the same stamp, so its rows are
    /// already excluded by the `deletedAt` filter (and the sub-query says so
    /// too). Ordering is `createdAt`, matching the per-car query's stable
    /// order; grouping and the urgency sort are the caller's read-time
    /// decision (`ReminderListGroups.grouped`).
    public func liveRemindersAcrossVehicles() throws -> [Reminder] {
        try database.read { db in
            try ReminderRow
                .filter(sql: """
                    deletedAt IS NULL AND vehicleId IN (
                        SELECT id FROM \(TankbookSchema.vehicle)
                        WHERE deletedAt IS NULL AND archived = 0)
                    """)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.reminder)
        }
    }
}
