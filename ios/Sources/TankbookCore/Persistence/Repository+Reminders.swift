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
    ///   selection, with its reminders stripped on archive (RV.81; J13,
    ///   `VehicleSelection.resolve`, `VehicleDetailView.toggleArchive`). A sold
    ///   car's pending oil change is history, not a task for the coming
    ///   weekend; surfacing it here would compete with live cars' work for the
    ///   user's attention. Its rows are not lost: archive never deletes or
    ///   tombstones them (hard rule 8) - they are hidden from every display
    ///   surface while the car is archived (the per-car door is gone with the
    ///   car, RV.81) and return to this list the moment the car is unarchived -
    ///   the exclusion is a read-time derivation, never a stored state.
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

// MARK: - History (RV.248)

extension TankbookRepository {
    /// Terminal reminders (`.done` / `.dismissed`) across every ACTIVE vehicle,
    /// most recently updated first - the History surface's query (RV.248,
    /// docs/JOURNEYS.md J7c -> "Delete", docs/SCREENMAP.md -> "Reminders across
    /// cars"). It is deliberately the mirror of `liveRemindersAcrossVehicles`:
    /// the same active-vehicle and tombstone rules, the opposite status half.
    /// Archived cars' terminal rows are excluded with their live ones, because
    /// archive hides a sold car's reminders from every display surface while
    /// keeping them (hard rule 8, J13); unarchiving returns both halves.
    ///
    /// `status` is stored as JSON, so the terminal filter runs over the decoded
    /// rows (`ReminderLifecycle.isActive`) rather than in SQL - the same
    /// derivation the rest of the app uses, never a second status parser.
    public func reminderHistoryAcrossVehicles() throws -> [Reminder] {
        let all = try database.read { db in
            try ReminderRow
                .filter(sql: """
                    deletedAt IS NULL AND vehicleId IN (
                        SELECT id FROM \(TankbookSchema.vehicle)
                        WHERE deletedAt IS NULL AND archived = 0)
                    """)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.reminder)
        }
        return all.filter { !ReminderLifecycle.isActive($0) }
    }

    /// The selected car's terminal reminders, most recently updated first - the
    /// per-car History section. Same tombstone and terminal rules as the
    /// merged query; no archived-car clause is needed because a selected
    /// vehicle is always active (`VehicleSelection.resolve`).
    public func reminderHistory(forVehicle vehicleId: UUID) throws -> [Reminder] {
        let all = try database.read { db in
            try ReminderRow
                .filter(Column("vehicleId") == vehicleId.uuidString
                        && Column("deletedAt") == nil)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.reminder)
        }
        return all.filter { !ReminderLifecycle.isActive($0) }
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
    ///   for every LIVE reminder, archived car or not. RV.81 changed WHY that
    ///   is: archiving now CANCELS a car's pending notifications, but nothing
    ///   can recall one the system already delivered, and a tap can race the
    ///   archive action (the notification was handed to the system a moment
    ///   before the user archived). Those taps must still land somewhere honest
    ///   rather than dead-end, which is hard rule 7 - so the resolve stays, and
    ///   a notification that slipped through the strip still surfaces its
    ///   completion over the merged list. Reusing the list query would make that
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
