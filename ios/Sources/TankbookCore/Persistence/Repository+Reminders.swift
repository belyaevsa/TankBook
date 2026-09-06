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

// MARK: - Resolve by id (RV.74)

extension TankbookRepository {
    /// The by-id resolve behind a tapped reminder notification (RV.74,
    /// docs/SCREENMAP.md -> "Reminders across cars"): the ONE live reminder
    /// matching an id, across EVERY vehicle - **archived cars included**. It
    /// answers a different question than `liveRemindersAcrossVehicles`, which is
    /// why it is not that query and deliberately does not reuse it:
    ///
    /// - The merged-list query feeds "what needs me now", so it excludes
    ///   archived cars' rows by decision (their work is history, J13).
    /// - A resolve answers "which car does this id belong to", and must answer
    ///   for every LIVE reminder, archived car or not - archive does not cancel
    ///   armed notifications, so an armed notification on an archived car is
    ///   still a tap the user can make. Reusing the list query would make that
    ///   tap unresolvable, which is the dead end hard rule 7 forbids.
    ///
    /// Live-row-only, exactly like every list query: a tombstoned row
    /// (`deletedAt != nil`) - a reminder deleted since its notification was
    /// scheduled - resolves to `nil`, so the caller takes its stale-tap landing
    /// (a plain list, never an error). A row whose vehicle was soft-deleted is
    /// tombstoned with it, so it resolves to `nil` too.
    public func liveReminder(id: UUID) throws -> Reminder? {
        try database.read { db in
            try ReminderRow
                .filter(Column("id") == id.uuidString && Column("deletedAt") == nil)
                .fetchOne(db)?
                .reminder
        }
    }
}
