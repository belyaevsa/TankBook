import Foundation
import Testing
@testable import TankbookCore

/// RV.75 - the cross-vehicle reminder query and the merged list's grouping.
/// docs/SCREENMAP.md -> "Reminders across cars", design/screens/
/// RemindersAll.dc.html. The gate is the two things a merged list must do that
/// a per-car list never had to: return every ACTIVE car's live reminders from
/// ONE query, and interleave two cars' rows by urgency rather than grouping by
/// car.
@Suite struct ReminderCrossVehicleTests {

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
                              dueInDays: Int,
                              createdAt: Date? = nil) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicleId, title: title, category: .oil,
            dueDate: now.addingTimeInterval(TimeInterval(dueInDays) * 86_400),
            dueOdometer: nil,
            createdAt: createdAt ?? now.addingTimeInterval(TimeInterval(dueInDays)))
    }

    // MARK: - The cross-vehicle query

    /// The query's whole point: one call returns live reminders from EVERY
    /// active vehicle - not the selected car, not the first car.
    @Test func liveAcrossVehiclesReturnsEveryActiveVehicle() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(skoda)

        let volvoReminder = makeReminder(vehicleId: volvo.id, title: "Volvo due", dueInDays: 3)
        let skodaReminder = makeReminder(vehicleId: skoda.id, title: "Skoda due", dueInDays: 5)
        try repo.upsertReminder(volvoReminder)
        try repo.upsertReminder(skodaReminder)

        let across = try repo.liveRemindersAcrossVehicles()
        #expect(Set(across.map(\.id)) == Set([volvoReminder.id, skodaReminder.id]),
                "the merged query must return BOTH cars' live reminders; got \(across.map(\.title))")
    }

    /// Tombstoned rows are excluded, exactly as the per-car query excludes them
    /// (hard rule 8 - a deleted reminder is in the 30-day undo window, never on
    /// a live list).
    @Test func liveAcrossVehiclesExcludesTombstonedRows() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        try repo.upsertVehicle(volvo)
        let live = makeReminder(vehicleId: volvo.id, title: "Live", dueInDays: 3)
        let deleted = makeReminder(vehicleId: volvo.id, title: "Deleted", dueInDays: 9)
        try repo.upsertReminder(live)
        try repo.upsertReminder(deleted)
        try repo.softDeleteReminder(id: deleted.id)

        let across = try repo.liveRemindersAcrossVehicles()
        #expect(across.map(\.id) == [live.id])
    }

    /// RV.75's recorded decision: archived cars' rows are excluded, because the
    /// merged list answers "what needs me" and an archived car is a sold car
    /// (J13). This test asserts the decision the doc comment records; flipping
    /// it is a product change, not a bug fix.
    @Test func liveAcrossVehiclesExcludesArchivedCarsRows() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let sold = makeVehicle("Sold BMW", archived: true)
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(sold)

        let volvoReminder = makeReminder(vehicleId: volvo.id, title: "Volvo due", dueInDays: 3)
        let soldReminder = makeReminder(vehicleId: sold.id, title: "Sold car due", dueInDays: 3)
        try repo.upsertReminder(volvoReminder)
        try repo.upsertReminder(soldReminder)

        let across = try repo.liveRemindersAcrossVehicles()
        #expect(across.map(\.id) == [volvoReminder.id],
                "an archived car's reminder must not compete with live cars' work")
        #expect(!across.contains { $0.id == soldReminder.id })
    }

    // MARK: - The merged grouping (interleaves by urgency, never by car)

    /// The list's sorting rule (docs/SCREENMAP.md): a date reminder and an
    /// odometer reminder interleave by urgency - a row that sorted by car first
    /// would answer "which car" instead of "what needs me". Two cars, their due
    /// dates staggered so the urgency order alternates cars; grouping by car
    /// would put both Volvo rows first.
    @Test func groupingInterleavesTwoCarsByUrgencyNotByCar() throws {
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")

        // Volvo rows due at +30 and +60 days, Skoda rows at +20 and +40 - all
        // scheduled (beyond the 12-day window). Urgency order alternates cars.
        let volvoSoon = makeReminder(vehicleId: volvo.id, title: "Volvo 30", dueInDays: 30)
        let volvoLate = makeReminder(vehicleId: volvo.id, title: "Volvo 60", dueInDays: 60)
        let skodaSoon = makeReminder(vehicleId: skoda.id, title: "Skoda 20", dueInDays: 20)
        let skodaLate = makeReminder(vehicleId: skoda.id, title: "Skoda 40", dueInDays: 40)

        let rows = [ReminderListRow(reminder: volvoSoon, currentOdometer: nil),
                    ReminderListRow(reminder: volvoLate, currentOdometer: nil),
                    ReminderListRow(reminder: skodaSoon, currentOdometer: nil),
                    ReminderListRow(reminder: skodaLate, currentOdometer: nil)]

        let result = ReminderListGroups.grouped(rows, now: now)

        #expect(result.attention.isEmpty)
        #expect(result.scheduled.map(\.reminder.title) == ["Skoda 20", "Volvo 30", "Skoda 40", "Volvo 60"],
                "urgency must interleave the two cars' rows, never group by car")
    }

    /// The attention half derives per row against ITS OWN vehicle's odometer:
    /// two odometer reminders with the same kilometres-to-due land in different
    /// groups when their cars' current readings differ. The merged list must
    /// never judge every row against one shared odometer.
    @Test func attentionIsJudgedAgainstEachRowsOwnCarOdometer() throws {
        let volvo = ReminderListRow(reminder: ReminderLifecycle.makeReminder(
            vehicleId: UUID.v7(), title: "Volvo service", category: .oil,
            dueDate: nil, dueOdometer: 118_400), currentOdometer: 118_000)
        let skoda = ReminderListRow(reminder: ReminderLifecycle.makeReminder(
            vehicleId: UUID.v7(), title: "Skoda service", category: .oil,
            dueDate: nil, dueOdometer: 200_900), currentOdometer: 200_000)

        let result = ReminderListGroups.grouped([volvo, skoda], now: now)

        #expect(result.attention.map(\.reminder.title) == ["Volvo service"],
                "400 km to due is attention, 900 km is not - judged against each row's own car")
        #expect(result.scheduled.map(\.reminder.title) == ["Skoda service"])
    }
}
