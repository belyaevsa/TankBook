import Foundation
import Testing
@testable import TankbookCore

/// RV.76 - the Home row's attention count
/// (`ReminderListGroups.attentionCount`). The count is the point of the calm
/// door into Reminders: it is DERIVED at read time (hard rule 2) from the live
/// reminders across every active car - never stored, never seeded as a number -
/// and it must agree with the merged list's "Needs attention" group by
/// construction, because it IS that group's count. docs/SCREENMAP.md ->
/// "Reminders across cars", design/screens/RemindersEntry.dc.html.
@Suite struct ReminderEntryCountTests {

    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeVehicle(_ name: String,
                             archived: Bool = false) -> Vehicle {
        let stamp = now
        return Vehicle(
            id: UUID.v7(), createdAt: stamp, updatedAt: stamp, deletedAt: nil,
            name: name, make: "Maker", model: name, year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: archived, paceLimitKmPerDay: 1500,
            initialOdometer: 100_000)
    }

    private func makeDateReminder(vehicleId: UUID,
                                  title: String,
                                  dueInDays: Int,
                                  status: ReminderStatus = .scheduled) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicleId, title: title, category: .oil,
            dueDate: now.addingTimeInterval(TimeInterval(dueInDays) * 86_400),
            dueOdometer: nil,
            status: status)
    }

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    /// The count's whole point: it spans EVERY active vehicle. Two cars each
    /// carrying one in-window reminder count 2 - the "when two things are due
    /// on different cars the second must not be invisible" case - and rows
    /// outside the attention window do not add to it.
    @Test func countSpansEveryLiveVehicle() throws {
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        let rows = [
            ReminderListRow(reminder: makeDateReminder(vehicleId: volvo.id, title: "Volvo due", dueInDays: 3),
                            currentOdometer: nil),
            ReminderListRow(reminder: makeDateReminder(vehicleId: skoda.id, title: "Skoda due", dueInDays: 8),
                            currentOdometer: nil),
            ReminderListRow(reminder: makeDateReminder(vehicleId: volvo.id, title: "Volvo later", dueInDays: 45),
                            currentOdometer: nil),
            ReminderListRow(reminder: makeDateReminder(vehicleId: skoda.id, title: "Skoda later", dueInDays: 90),
                            currentOdometer: nil)
        ]
        #expect(ReminderListGroups.attentionCount(rows, now: now) == 2,
                "both cars' in-window reminders must count; scheduled ones must not")
    }

    /// The count is judged per row against ITS OWN car's odometer: two
    /// odometer reminders with the same kilometres-to-due land differently when
    /// their cars' readings differ - the merged list's rule, so the Home count
    /// cannot disagree with the list it opens.
    @Test func countIsJudgedAgainstEachRowsOwnCarOdometer() throws {
        let volvo = ReminderListRow(reminder: ReminderLifecycle.makeReminder(
            vehicleId: UUID.v7(), title: "Volvo service", category: .oil,
            dueDate: nil, dueOdometer: 118_400), currentOdometer: 118_000)
        let skoda = ReminderListRow(reminder: ReminderLifecycle.makeReminder(
            vehicleId: UUID.v7(), title: "Skoda service", category: .oil,
            dueDate: nil, dueOdometer: 200_900), currentOdometer: 200_000)

        #expect(ReminderListGroups.attentionCount([volvo, skoda], now: now) == 1,
                "400 km to due counts, 900 km does not - each against its own car")
    }

    /// Terminal rows never re-derive (docs/SCHEMA.md), so they never count: a
    /// completed or dismissed reminder is history, not a task for the weekend.
    @Test func countExcludesTerminalRows() throws {
        let done = ReminderListRow(reminder: makeDateReminder(
            vehicleId: UUID.v7(), title: "Done oil", dueInDays: 2,
            status: .done(entryId: nil)), currentOdometer: nil)
        let dismissed = ReminderListRow(reminder: makeDateReminder(
            vehicleId: UUID.v7(), title: "Dismissed", dueInDays: 4,
            status: .dismissed(reason: nil)), currentOdometer: nil)
        #expect(ReminderListGroups.attentionCount([done, dismissed], now: now) == 0,
                "a .done or .dismissed row is history, never an attention count")
    }

    /// The count is derived, never stored: seeded from the repository's live
    /// rows it reads 2; completing one reminder (a live-row change) makes the
    /// NEXT read 1 with nothing re-seeded and no stored count anywhere. This is
    /// the whole shape of the RV.76 Home row - a number that recomputes itself.
    @Test func countDerivesFromLiveRowsAndIsNeverStored() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(skoda)

        let volvoReminder = makeDateReminder(vehicleId: volvo.id, title: "Volvo due", dueInDays: 3)
        let skodaReminder = makeDateReminder(vehicleId: skoda.id, title: "Skoda due", dueInDays: 9)
        try repo.upsertReminder(volvoReminder)
        try repo.upsertReminder(skodaReminder)

        func readCount() throws -> Int {
            let across = try repo.liveRemindersAcrossVehicles()
            let rows = across.map { ReminderListRow(reminder: $0, currentOdometer: nil) }
            return ReminderListGroups.attentionCount(rows, now: now)
        }

        #expect(try readCount() == 2, "both live reminders are in the window")

        // Complete one: .done is a stored transition, but the COUNT is derived,
        // so the next read drops to 1 without any stored count being touched.
        let completed = ReminderLifecycle.complete(
            volvoReminder, entryId: nil,
            completionDate: now, completionOdometer: nil, now: now).completed
        try repo.upsertReminder(completed)

        #expect(try readCount() == 1,
                "the count must re-derive from the live rows, never from a stored number")
    }
}
