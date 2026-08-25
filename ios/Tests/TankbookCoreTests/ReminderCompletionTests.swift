import Foundation
import Testing
@testable import TankbookCore

/// P3.5 completion-chain tests (docs/SCHEMA.md -> "Reminder lifecycle
/// (normative)", docs/JOURNEYS.md J7c). These drive the COMPLETE -> pre-filled
/// entry -> `.done(entryId)` -> next-occurrence chain through a real in-memory
/// repository, so what they assert is the persisted result, not a pure-function
/// projection. The pure transition table lives in `ReminderLifecycleTests`;
/// this suite asserts the P3.5 wiring: the pre-fill mapping, the entry id
/// handed to the reminder, and the two rows (history + next) on disk.
@Suite struct ReminderCompletionTests {

    private static let vehicleID = UUID.v7()

    private func makeReminder(
        status: ReminderStatus = .scheduled,
        category: ReminderCategory = .oil,
        title: String = "Oil change",
        dueDate: Date? = Date(timeIntervalSince1970: 1_752_000_000),
        dueOdometer: Int? = 120_000,
        recurrence: Reminder.Recurrence? = nil,
        vehicleId: UUID = ReminderCompletionTests.vehicleID,
        createdAt: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> Reminder {
        Reminder(
            id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt, deletedAt: nil,
            vehicleId: vehicleId, title: title, category: category,
            dueDate: dueDate, dueOdometer: dueOdometer,
            recurrence: recurrence, sourceEntryId: nil, status: status)
    }

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle() -> Vehicle {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        return Vehicle(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
    }

    /// Builds the pre-filled service record from a prefill, through the SAME
    /// `ServiceEntryDraft.build` the ServiceEntry screen uses (never a
    /// hand-rolled record) so the chain test exercises the real save path.
    private func buildService(from prefill: ReminderCompletion.Prefill,
                              vehicleId: UUID,
                              now: Date) throws -> ServiceRecord {
        guard case .service(let category) = prefill.kind else {
            throw TestError.wrongKind
        }
        let draft = ServiceEntryDraft(
            vendor: nil,
            items: [ServiceItem.make(title: prefill.title, category: category)],
            date: now,
            odometer: prefill.odometer)
        return draft.build(vehicleId: vehicleId, homeCurrency: .eur, now: now)
    }

    private enum TestError: Error {
        case wrongKind
    }

    // MARK: - The chain, end to end

    /// COMPLETE -> a pre-filled entry is saved -> the reminder is
    /// `.done(entryId)` carrying THAT entry's id -> the next occurrence exists
    /// as a NEW row and the old row survives as history.
    @Test func chainEndToEndThroughRepository() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let completionDate = Date(timeIntervalSince1970: 1_753_600_000)
        let reminder = makeReminder(
            dueDate: Date(timeIntervalSince1970: 1_751_000_000),
            dueOdometer: 120_000,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12),
            vehicleId: vehicle.id)
        try repo.upsertReminder(reminder)

        // 1. The pre-fill the completion sheet produces.
        let prefill = ReminderCompletion.prefill(for: reminder, currentOdometer: 118_930)
        #expect(prefill.title == "Oil change")
        #expect(prefill.odometer == 118_930)

        // 2. The pre-filled entry is saved (the user typed a total and saved).
        let service = try buildService(from: prefill, vehicleId: vehicle.id, now: completionDate)
        try repo.upsertServiceRecord(service)

        // 3. Completion is keyed on that entry's real id.
        let result = ReminderLifecycle.complete(
            reminder, entryId: service.id,
            completionDate: completionDate, completionOdometer: 118_930)
        try ReminderCompletion.persist(result, repository: repo)

        // 4. On disk: the old row survives as history carrying the entry id...
        let live = try repo.liveReminders(forVehicle: vehicle.id)
        let completed = live.first { $0.id == reminder.id }
        #expect(completed?.status == .done(entryId: service.id),
                "the reminder is .done with the entry's own id")
        #expect(completed?.dueDate == reminder.dueDate,
                "history keeps its original due")
        #expect(completed?.dueOdometer == reminder.dueOdometer,
                "history keeps its original due")

        // ...and the next occurrence is a NEW row.
        let next = live.first { $0.id != reminder.id }
        #expect(next != nil, "the next occurrence is a new row")
        #expect(next?.status == .scheduled)
        #expect(next?.sourceEntryId == service.id,
                "the next row links to the completion's entry via sourceEntryId")
        #expect(try repo.rowCount(in: TankbookSchema.reminder) == 2,
                "exactly two rows: the history row and the next occurrence")
    }

    // MARK: - Anchored at completion, not at the due date

    /// Complete a reminder LATE and assert the persisted next occurrence is
    /// measured from the COMPLETION date/odometer. Completing on time cannot
    /// distinguish the two anchorings; the literal expectations below are the
    /// wrong values if the code anchored at the due date.
    @Test func completionAnchorsAtCompletionThroughRepository() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let dueDate = Date(timeIntervalSince1970: 1_751_000_000)       // 30 days before...
        let completionDate = Date(timeIntervalSince1970: 1_753_600_000) // ...now
        let reminder = makeReminder(
            status: .attention, dueDate: dueDate, dueOdometer: 120_000,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12),
            vehicleId: vehicle.id)
        try repo.upsertReminder(reminder)

        let result = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: completionDate, completionOdometer: 118_930)
        try ReminderCompletion.persist(result, repository: repo)

        let next = try repo.liveReminders(forVehicle: vehicle.id).first { $0.id != reminder.id }
        #expect(next != nil, "the late completion must still create the next row")

        // Anchored at COMPLETION (literals, never recomputed through the code
        // under test): completion date + 12 months, completion odometer + 15 000.
        let expectedDate = Calendar.current.date(byAdding: .month, value: 12, to: completionDate)
        #expect(next?.dueDate == expectedDate,
                "anchored at the completion date, not the original due")
        #expect(next?.dueOdometer == 133_930,
                "anchored at the completion odometer: 118 930 + 15 000")

        // The due-anchored values are the drift this test proves wrong.
        #expect(next?.dueDate != Calendar.current.date(byAdding: .month, value: 12, to: dueDate))
        #expect(next?.dueOdometer != 135_000)
    }

    // MARK: - Declining the cost prompt still completes

    /// Skip yields `.done(nil)`, NO entry row is written, and the next
    /// occurrence is still created when recurrence is set.
    @Test func decliningStillCompletesWithNoEntryWrittenThroughRepository() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let completionDate = Date(timeIntervalSince1970: 1_753_600_000)
        let reminder = makeReminder(
            recurrence: Reminder.Recurrence(everyKm: nil, everyMonths: 12),
            vehicleId: vehicle.id)
        try repo.upsertReminder(reminder)

        let result = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: completionDate, completionOdometer: nil)
        try ReminderCompletion.persist(result, repository: repo)

        let live = try repo.liveReminders(forVehicle: vehicle.id)
        let completed = live.first { $0.id == reminder.id }
        #expect(completed?.status == .done(entryId: nil),
                "declined cost log is a valid terminal state")

        // No entry was written - the whole point of the decline path.
        #expect(try repo.liveServiceRecords(forVehicle: vehicle.id).isEmpty,
                "declining must not write a service record")
        #expect(try repo.liveExpenses(forVehicle: vehicle.id).isEmpty,
                "declining must not write an expense")

        let next = live.first { $0.id != reminder.id }
        #expect(next != nil, "declining must not break the recurrence loop")
        #expect(next?.sourceEntryId == nil,
                "no entry was created, so no sourceEntryId")
    }

    // MARK: - A non-recurring reminder produces no next occurrence

    @Test func nonRecurringProducesNoNextOccurrenceThroughRepository() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let completionDate = Date(timeIntervalSince1970: 1_753_600_000)
        let reminder = makeReminder(recurrence: nil, vehicleId: vehicle.id)
        try repo.upsertReminder(reminder)

        let result = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: completionDate, completionOdometer: 118_930)
        try ReminderCompletion.persist(result, repository: repo)

        #expect(result.nextOccurrence == nil,
                "no recurrence means no next occurrence")
        #expect(try repo.rowCount(in: TankbookSchema.reminder) == 1,
                "only the history row remains")
    }

    // MARK: - The pre-fill is editable (hard rule 13)

    /// The pre-fill arrives as defaults and every one can change before saving,
    /// and the reminder transition is keyed on the entry id - never on the
    /// pre-fill values - so editing title/category/odometer is free.
    @Test func prefillIsADefaultNotAFact() {
        let reminder = makeReminder(
            category: .oil, title: "Oil change",
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))

        // The prefill starts from the reminder's values...
        let prefill = ReminderCompletion.prefill(for: reminder, currentOdometer: 118_930)
        #expect(prefill.title == "Oil change")
        #expect(prefill.odometer == 118_930)
        #expect(prefill.kind == .service(.oil))

        // ...but an entry can diverge from all three axes and still save. The
        // completion then keys on the entry id and the EDITED odometer.
        let editedTitle = "Brake fluid"
        let editedOdometer = 121_000
        let completionDate = Date(timeIntervalSince1970: 1_753_600_000)
        let entryID = UUID.v7()

        let draft = ServiceEntryDraft(
            vendor: nil,
            items: [ServiceItem.make(title: editedTitle, category: .brakes)],
            date: completionDate,
            odometer: editedOdometer)
        let service = draft.build(vehicleId: ReminderCompletionTests.vehicleID,
                                  homeCurrency: .eur, now: completionDate)

        let result = ReminderLifecycle.complete(
            reminder, entryId: service.id,
            completionDate: completionDate, completionOdometer: editedOdometer)

        #expect(result.completed.status == .done(entryId: service.id))
        #expect(result.nextOccurrence?.sourceEntryId == service.id)
        // The user's edited odometer anchors the next occurrence - the edit
        // flows through; the prefill title/category never touch the reminder.
        #expect(result.nextOccurrence?.dueOdometer == 121_000 + 15_000)
    }

    // MARK: - The category mapping

    /// Every reminder category maps to the entry the pre-fill opens: insurance
    /// to an expense, service categories to their ServiceCategory twin, and
    /// custom/other to a free-text service item so nothing falls through.
    @Test func entryKindMapsEveryCategory() {
        #expect(ReminderCompletion.entryKind(for: .insurance) == .expense(.insurance))
        #expect(ReminderCompletion.entryKind(for: .oil) == .service(.oil))
        #expect(ReminderCompletion.entryKind(for: .brakes) == .service(.brakes))
        #expect(ReminderCompletion.entryKind(for: .tires) == .service(.tires))
        #expect(ReminderCompletion.entryKind(for: .battery) == .service(.battery))
        #expect(ReminderCompletion.entryKind(for: .filters) == .service(.filters))
        #expect(ReminderCompletion.entryKind(for: .inspection) == .service(.inspection))
        #expect(ReminderCompletion.entryKind(for: .repair) == .service(.repair))
        #expect(ReminderCompletion.entryKind(for: .parts) == .service(.parts))
        #expect(ReminderCompletion.entryKind(for: .wash) == .service(.wash))
        #expect(ReminderCompletion.entryKind(for: .custom) == .service(.other("")))
        #expect(ReminderCompletion.entryKind(for: .other("lube")) == .service(.other("lube")))
    }
}
