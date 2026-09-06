import Foundation
import Testing
@testable import TankbookCore

/// RV.74 - the by-id resolve behind a tapped reminder notification. The gate
/// is that an id resolves to ITS reminder - on any live vehicle, ARCHIVED cars
/// included - while a tombstoned row resolves to nothing. This is the query
/// the deep link's car switch and archived landing read; the merged-list query
/// answers a different question and deliberately does not serve it.
@Suite struct ReminderResolveTests {

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
                              id: UUID = UUID.v7()) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicleId, title: title, category: .oil,
            dueDate: now.addingTimeInterval(10 * 86_400),
            dueOdometer: nil,
            createdAt: now,
            id: id)
    }

    // MARK: - The resolve

    /// A tapped notification names a reminder id; the resolve returns THAT
    /// reminder so the caller can reach its vehicle. The id is the fact, never
    /// the selected car.
    @Test func liveReminderResolvesByIdAcrossVehicles() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(skoda)

        let target = makeReminder(vehicleId: skoda.id, title: "Skoda due", id: UUID.v7())
        try repo.upsertReminder(target)
        try repo.upsertReminder(makeReminder(vehicleId: volvo.id, title: "Volvo due"))

        let resolved = try repo.liveReminder(id: target.id)
        #expect(resolved?.id == target.id)
        #expect(resolved?.vehicleId == skoda.id,
                "the resolve must land on the reminder's OWN car, never the first or selected one")
    }

    /// The recorded difference from the merged-list query: a resolve must answer
    /// for EVERY live reminder, archived car or not. RV.81 changed the reason -
    /// archiving now cancels a car's PENDING notifications, but nothing can
    /// recall one already delivered, and a tap can race the archive action - so
    /// an archived car's reminder can still be tapped and must still land
    /// somewhere honest (hard rule 7). The merged-list query excludes the same
    /// row by decision; that is exactly why the deep link cannot reuse it.
    @Test func liveReminderResolvesAnArchivedCarsReminder() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let sold = makeVehicle("Sold BMW", archived: true)
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(sold)

        let soldReminder = makeReminder(vehicleId: sold.id, title: "Sold car due")
        try repo.upsertReminder(soldReminder)

        let resolved = try repo.liveReminder(id: soldReminder.id)
        #expect(resolved?.id == soldReminder.id,
                "a live reminder on an archived car must still resolve - an armed tap on it must not dead-end")
        #expect(try repo.liveRemindersAcrossVehicles().allSatisfy { $0.id != soldReminder.id },
                "the merged list excludes the archived row while the resolve answers it - two different jobs")
    }

    /// A tombstoned reminder - deleted since its notification was scheduled -
    /// resolves to nothing, so the deep link takes its stale-tap landing (a
    /// plain list, never an error - hard rule 7).
    @Test func liveReminderTombstonedResolvesToNothing() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        try repo.upsertVehicle(volvo)

        let deleted = makeReminder(vehicleId: volvo.id, title: "Deleted due")
        try repo.upsertReminder(deleted)
        try repo.softDeleteReminder(id: deleted.id)

        #expect(try repo.liveReminder(id: deleted.id) == nil)
    }

    /// An id that was never a reminder (or a malformed tap) resolves to
    /// nothing - the same stale landing, never a dead end.
    @Test func liveReminderUnknownIdResolvesToNothing() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        try repo.upsertVehicle(volvo)
        try repo.upsertReminder(makeReminder(vehicleId: volvo.id, title: "Volvo due"))

        #expect(try repo.liveReminder(id: UUID.v7()) == nil)
    }

    /// A terminal row (.done/.dismissed) is still a live row - history, not a
    /// tombstone - so it resolves. The CALLER decides whether to re-surface its
    /// completion flow (`ReminderLifecycle.isActive`); the resolve itself must
    /// not drop it, or an edit/undo path would lose it.
    @Test func liveReminderResolvesADoneRow() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        try repo.upsertVehicle(volvo)

        let done = ReminderLifecycle.makeReminder(
            vehicleId: volvo.id, title: "Done due", category: .oil,
            dueDate: nil, dueOdometer: nil,
            status: .done(entryId: nil))
        try repo.upsertReminder(done)

        #expect(try repo.liveReminder(id: done.id)?.id == done.id,
                "a done row is history, not deleted - it must resolve")
    }
}
