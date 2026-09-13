import Foundation
import Testing
@testable import TankbookCore

/// RV.248 - the reminder History read side (docs/JOURNEYS.md J7c -> "Delete",
/// docs/SCHEMA.md -> Reminder lifecycle). Before this row the dismissal reason
/// and the completion's `entryId` were collected, persisted and synced, and
/// read by nothing; these tests pin the query that reads them back and the
/// values a History row carries. The named mutation - filtering the query to
/// active rows - turns `historyAcrossVehiclesReturnsTerminalRows` red.
@Suite struct ReminderHistoryTests {

    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle(_ name: String,
                             archived: Bool = false,
                             id: UUID = UUID.v7()) -> Vehicle {
        Vehicle(
            id: id, createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, make: "Maker", model: name, year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 60, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: archived, paceLimitKmPerDay: 1500,
            initialOdometer: 100_000)
    }

    private func reminder(vehicleId: UUID,
                          title: String,
                          status: ReminderStatus,
                          createdAt: Date? = nil) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicleId, title: title, category: .oil,
            dueDate: now.addingTimeInterval(-10 * 86_400), dueOdometer: nil,
            recurrence: nil, status: status,
            createdAt: createdAt ?? now)
    }

    // MARK: - The query

    /// The query the History surface reads: terminal rows come back WITH the
    /// reason the dismissal collected and the entry the completion logged, and
    /// live rows stay out.
    @Test func historyAcrossVehiclesReturnsTerminalRowsWithTheirData() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        try repo.upsertVehicle(volvo)

        let entryId = UUID.v7()
        let done = reminder(vehicleId: volvo.id, title: "Oil change",
                            status: .done(entryId: entryId),
                            createdAt: now.addingTimeInterval(-20 * 86_400))
        let dismissed = reminder(vehicleId: volvo.id, title: "Winter tires",
                                 status: .dismissed(reason: "Sold the tires"),
                                 createdAt: now.addingTimeInterval(-10 * 86_400))
        let live = reminder(vehicleId: volvo.id, title: "Insurance renewal",
                            status: .scheduled, createdAt: now)
        try repo.upsertReminder(done)
        try repo.upsertReminder(dismissed)
        try repo.upsertReminder(live)

        let history = try repo.reminderHistoryAcrossVehicles()
        #expect(Set(history.map(\.id)) == Set([done.id, dismissed.id]),
                "history must return exactly the terminal rows; got \(history.map(\.title))")
        #expect(!history.contains { $0.id == live.id },
                "a live reminder is work, not history")

        let storedDismissal = history.first { $0.id == dismissed.id }
        #expect(ReminderHistory.dismissalReason(of: storedDismissal!) == "Sold the tires",
                "the stored reason must survive the round trip to the history surface")
        let storedDone = history.first { $0.id == done.id }
        #expect(ReminderHistory.completedEntryId(of: storedDone!) == entryId,
                "a done row must name the entry its completion logged")
    }

    /// The mirror of the live query's exclusions: tombstones and archived cars'
    /// rows are not history (hard rule 8 keeps them, the surfaces hide them).
    @Test func historyAcrossVehiclesExcludesTombstonesAndArchivedCars() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let sold = makeVehicle("Sold BMW", archived: true)
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(sold)

        let kept = reminder(vehicleId: volvo.id, title: "Oil change",
                            status: .done(entryId: nil))
        let deleted = reminder(vehicleId: volvo.id, title: "Brakes",
                               status: .done(entryId: nil),
                               createdAt: now.addingTimeInterval(-86_400))
        let soldRow = reminder(vehicleId: sold.id, title: "Sold car service",
                               status: .done(entryId: nil))
        try repo.upsertReminder(kept)
        try repo.upsertReminder(deleted)
        try repo.upsertReminder(soldRow)
        try repo.softDeleteReminder(id: deleted.id)

        let history = try repo.reminderHistoryAcrossVehicles()
        #expect(history.map(\.id) == [kept.id],
                "tombstones and archived cars' rows must not surface as history")
    }

    /// The per-car query answers only its car, and still only its terminal rows.
    @Test func historyForVehicleStaysScopedToThatCar() throws {
        let repo = try makeRepository()
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(skoda)

        let volvoDone = reminder(vehicleId: volvo.id, title: "Oil change",
                                 status: .done(entryId: nil))
        let skodaDone = reminder(vehicleId: skoda.id, title: "Inspection",
                                 status: .dismissed(reason: nil))
        let volvoLive = reminder(vehicleId: volvo.id, title: "Insurance",
                                 status: .scheduled)
        try repo.upsertReminder(volvoDone)
        try repo.upsertReminder(skodaDone)
        try repo.upsertReminder(volvoLive)

        let history = try repo.reminderHistory(forVehicle: volvo.id)
        #expect(history.map(\.id) == [volvoDone.id],
                "the per-car history must not leak another car's rows or its live work")
    }

    // MARK: - The row values

    /// The count line is the honest version of "oil changed 3x on time": the
    /// number of RECORDED completions of the same title on the same car, never
    /// a claim about timing the data cannot support.
    @Test func completionCountCountsCompletedSameTitleOnTheSameCar() throws {
        let volvo = makeVehicle("Volvo V60")
        let skoda = makeVehicle("Skoda Octavia")

        let first = reminder(vehicleId: volvo.id, title: "Oil change",
                             status: .done(entryId: UUID.v7()),
                             createdAt: now.addingTimeInterval(-30 * 86_400))
        let second = reminder(vehicleId: volvo.id, title: "Oil change",
                              status: .done(entryId: UUID.v7()),
                              createdAt: now.addingTimeInterval(-10 * 86_400))
        let otherTitle = reminder(vehicleId: volvo.id, title: "Inspection",
                                  status: .done(entryId: nil))
        let otherCar = reminder(vehicleId: skoda.id, title: "Oil change",
                                status: .done(entryId: nil))
        let dismissed = reminder(vehicleId: volvo.id, title: "Oil change",
                                 status: .dismissed(reason: "sold"))
        let terminal = [first, second, otherTitle, otherCar, dismissed]

        #expect(ReminderHistory.completionCount(of: first, among: terminal) == 2,
                "two completions of the same title on the same car count together")
        #expect(ReminderHistory.completionCount(of: otherTitle, among: terminal) == 1,
                "a different title on the same car is its own count")
        #expect(ReminderHistory.completionCount(of: otherCar, among: terminal) == 1,
                "the same title on another car must not be merged in")
        #expect(ReminderHistory.completionCount(of: dismissed, among: terminal) == 0,
                "a dismissal is not a completion")
    }

    /// The builder orders by the caller's order (the query's most-recent-first)
    /// and carries the reason and entry id through.
    @Test func rowsCarryReasonEntryIdAndOrder() throws {
        let volvo = makeVehicle("Volvo V60")
        let entryId = UUID.v7()
        let newer = reminder(vehicleId: volvo.id, title: "Winter tires",
                             status: .dismissed(reason: "Sold the tires"),
                             createdAt: now)
        let older = reminder(vehicleId: volvo.id, title: "Oil change",
                             status: .done(entryId: entryId),
                             createdAt: now.addingTimeInterval(-30 * 86_400))

        let rows = ReminderHistory.rows([newer, older])
        #expect(rows.map(\.reminder.id) == [newer.id, older.id],
                "the builder preserves the query's most-recent-first order")
        #expect(rows[0].completionCount == 0)
        #expect(ReminderHistory.dismissalReason(of: rows[0].reminder) == "Sold the tires")
        #expect(ReminderHistory.completedEntryId(of: rows[1].reminder) == entryId)
    }

    /// A whitespace-only reason is not a reason, and a live row handed to the
    /// builder is not history - the two defensive halves of the row values.
    @Test func blankReasonAndActiveRowsAreNotHistoryContent() throws {
        let volvo = makeVehicle("Volvo V60")
        let blank = reminder(vehicleId: volvo.id, title: "Tires",
                             status: .dismissed(reason: "   "))
        let live = reminder(vehicleId: volvo.id, title: "Insurance",
                            status: .attention)

        #expect(ReminderHistory.dismissalReason(of: blank) == nil)
        #expect(ReminderHistory.rows([blank, live]).map(\.reminder.id) == [blank.id],
                "an active row must never render as history")
    }
}
