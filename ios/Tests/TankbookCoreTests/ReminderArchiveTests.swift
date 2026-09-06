import Foundation
import Testing
@testable import TankbookCore

/// RV.81 (decided 2026-09-06) - archiving strips a car's reminders: its armed
/// notifications are cancelled and nothing is armed again while it stays
/// archived, but the ROWS are never deleted, tombstoned or dismissed - archive
/// is "put it away", not "lose it" (hard rule 8, docs/SCHEMA.md -> Reminder
/// lifecycle). These L1 tests pin the persistence half of that contract; the
/// notification-cancel half lives at L2 against the real
/// `UNUserNotificationCenter` (ReminderNotificationActionTests) because the
/// plan's archived branch is exercised through the coordinator's reconcile.
@Suite struct ReminderArchiveTests {

    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle(_ name: String,
                             archived: Bool = false,
                             id: UUID = UUID.v7()) -> Vehicle {
        let stamp = now
        return Vehicle(
            id: id, createdAt: stamp, updatedAt: stamp, deletedAt: nil,
            name: name, make: "Maker", model: name, year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: archived, paceLimitKmPerDay: 1500,
            initialOdometer: 100_000)
    }

    private func makeReminder(vehicleId: UUID,
                              title: String,
                              status: ReminderStatus = .scheduled,
                              id: UUID = UUID.v7()) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicleId, title: title, category: .oil,
            dueDate: now.addingTimeInterval(60 * 86_400),
            dueOdometer: nil,
            status: status,
            createdAt: now,
            id: id)
    }

    // MARK: - Archive never touches the rows

    /// The L1 contract the brief calls the "history test": archiving a car
    /// leaves every one of its reminder rows intact - present in the per-car
    /// live query, with its status unchanged and its `deletedAt` still nil.
    /// A test that asserts deletion is asserting the wrong thing: the mutation
    /// that tombstones (or dismisses) rows on archive must fail HERE.
    @Test func archivingLeavesReminderRowsIntact() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let sold = makeVehicle("Sold BMW")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(sold)

        let scheduled = makeReminder(vehicleId: sold.id, title: "Oil change",
                                     status: .scheduled)
        let fired = makeReminder(vehicleId: sold.id, title: "Insurance",
                                 status: .attention)
        try repo.upsertReminder(scheduled)
        try repo.upsertReminder(fired)

        try repo.archiveVehicle(id: sold.id)

        let rows = try repo.liveReminders(forVehicle: sold.id)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        #expect(Set(byID.keys) == Set([scheduled.id, fired.id]),
                "archiving must not delete or tombstone the car's reminder rows")
        #expect(byID[scheduled.id]?.status == .scheduled,
                "a .scheduled row stays .scheduled - archive never advances the lifecycle")
        #expect(byID[scheduled.id]?.deletedAt == nil,
                "an archived car's reminder is not tombstoned (hard rule 8)")
        #expect(byID[fired.id]?.status == .attention,
                "a stored .attention row stays .attention - archive never dismisses it")
        #expect(byID[fired.id]?.deletedAt == nil)
    }

    /// Archiving does not "complete" or "dismiss" a reminder as a side effect
    /// - the rows are exactly the rows the user will find when they unarchive
    /// the car. Asserting identity via status is the honest reading of "intact"
    /// (a dismiss would flip `.scheduled` to `.dismissed`, which the test above
    /// already forbids, but a done-row car makes the contrast visible).
    @Test func archivingLeavesDoneRowsDone() throws {
        let repo = try makeRepository()
        let sold = makeVehicle("Sold BMW")
        try repo.upsertVehicle(sold)
        let done = makeReminder(vehicleId: sold.id, title: "Past oil",
                                status: .done(entryId: nil))
        try repo.upsertReminder(done)

        try repo.archiveVehicle(id: sold.id)

        let rows = try repo.liveReminders(forVehicle: sold.id)
        #expect(rows.map(\.id) == [done.id],
                "history rows survive archiving too - they are the car's record")
        #expect(rows.first?.status == .done(entryId: nil))
    }

    // MARK: - The resolve still answers for an archived car

    /// RV.74/RV.81: a notification that the archive could not recall (already
    /// delivered to the system, or racing the archive action) must still
    /// resolve to its reminder so the tap lands somewhere honest rather than
    /// dead-ending (hard rule 7). Archiving strips PENDING notifications; the
    /// resolve is what the residue taps read.
    @Test func liveReminderStillResolvesAnArchivedCarsReminder() throws {
        let repo = try makeRepository()
        let sold = makeVehicle("Sold BMW", archived: true)
        try repo.upsertVehicle(sold)
        let reminder = makeReminder(vehicleId: sold.id, title: "Sold car due")
        try repo.upsertReminder(reminder)

        let resolved = try repo.liveReminder(id: reminder.id)
        #expect(resolved?.id == reminder.id,
                "the resolve must answer for an archived car's live reminder")
        #expect(resolved?.status == .scheduled,
                "the resolve reads the row as stored - archive never mutates it")
    }

    // MARK: - Unarchive restores visibility without touching rows

    /// The reverse direction of the same contract: unarchiving a car does not
    /// resurrect or duplicate rows (there is nothing to resurrect - they were
    /// never gone), and the rows are live again on every query. This pins the
    /// "rows come back when the car comes back" promise.
    @Test func unarchivingReturnsTheSameRows() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let sold = makeVehicle("Sold BMW")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(sold)
        let reminder = makeReminder(vehicleId: sold.id, title: "Oil change")
        try repo.upsertReminder(reminder)
        try repo.archiveVehicle(id: sold.id)

        try repo.unarchiveVehicle(id: sold.id)

        let rows = try repo.liveReminders(forVehicle: sold.id)
        #expect(rows.map(\.id) == [reminder.id],
                "unarchive must not duplicate or lose the rows the archive kept")
        #expect(rows.first?.status == .scheduled,
                "the row is byte-for-byte the row that was archived")
        let across = try repo.liveRemindersAcrossVehicles()
        #expect(across.map(\.id).contains(reminder.id),
                "an unarchived car's reminders return to the merged list")
    }
}
