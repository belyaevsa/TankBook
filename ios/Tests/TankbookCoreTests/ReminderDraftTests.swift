import Foundation
import Testing
@testable import TankbookCore

/// P3.4 ReminderDraft rules (docs/SCHEMA.md -> Reminder). The form's pure
/// decision layer: neither due field is mandatory on its own, but a reminder
/// with neither is not a reminder - it refuses to save and names its next step
/// (hard rule 7). The build path the tests drive here is the same one the form
/// calls, never a hand-rolled record.
@Suite struct ReminderDraftTests {

    private func makeVehicle() -> Vehicle {
        let timestamp = Date(timeIntervalSince1970: 1_752_000_000)
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

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    // MARK: - The no-due-field rule (the invariant this task exists for)

    @Test func neitherDueFieldRefusesToSaveAndNamesTheNextStep() {
        // Date-only: a perfectly good reminder.
        #expect(ReminderDraft(title: "Insurance renewal", category: .insurance,
                              dueDate: Date()).readiness == .ready)
        // Odometer-only: a perfectly good reminder.
        #expect(ReminderDraft(title: "Oil change", category: .oil,
                              dueOdometer: 130_000).readiness == .ready)
        // Both: fine.
        #expect(ReminderDraft(title: "Oil change", category: .oil,
                              dueDate: Date(), dueOdometer: 130_000).readiness == .ready)
        // Neither: refuses to save, and the reason names the next step.
        let neither = ReminderDraft(title: "Oil change", category: .oil)
        #expect(neither.readiness == .noDueField,
                "a reminder with neither due field is not a reminder")
    }

    @Test func blankTitleRefusesToSaveSeparately() {
        #expect(ReminderDraft(title: "", category: .oil, dueDate: Date()).readiness == .titleMissing)
        #expect(ReminderDraft(title: "   ", category: .oil, dueDate: Date()).readiness == .titleMissing)
        #expect(ReminderDraft(title: " ", category: .oil, dueDate: Date()).readiness == .titleMissing)
    }

    // MARK: - Build (the create path)

    @Test func buildProducesAScheduledReminderWithTheDraftsDecisions() {
        let vehicle = makeVehicle()
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let draft = ReminderDraft(title: "Oil change", category: .oil,
                                  dueDate: now, dueOdometer: 130_000,
                                  recurrenceEveryKm: 15_000, recurrenceEveryMonths: 12)

        let built = draft.build(vehicleId: vehicle.id, now: now)

        #expect(built.vehicleId == vehicle.id)
        #expect(built.title == "Oil change")
        #expect(built.category == .oil)
        #expect(built.dueDate == now)
        #expect(built.dueOdometer == 130_000)
        #expect(built.recurrence == Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        #expect(built.status == .scheduled)
        #expect(built.sourceEntryId == nil)
        #expect(built.createdAt == now)
        #expect(built.updatedAt == now)
        #expect(built.deletedAt == nil)
        #expect(built.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test func recurrenceZeroesAreTreatedAsUnset() {
        let draft = ReminderDraft(title: "Oil change", category: .oil,
                                  dueDate: Date(),
                                  recurrenceEveryKm: 0, recurrenceEveryMonths: 0)
        #expect(draft.recurrence == nil,
                "a zero in a recurrence field is a no-op, not a burst")
        let kmOnly = ReminderDraft(title: "Oil change", category: .oil,
                                   dueDate: Date(), recurrenceEveryKm: 15_000)
        #expect(kmOnly.recurrence == Reminder.Recurrence(everyKm: 15_000, everyMonths: nil))
    }

    @Test func builtReminderRoundTripsThroughPersistence() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)
        let draft = ReminderDraft(title: "Inspection (TÜV)", category: .inspection,
                                  dueDate: Date(timeIntervalSince1970: 1_754_000_000))
        let built = draft.build(vehicleId: vehicle.id)

        try repo.upsertReminder(built)
        let readBack = try repo.liveReminders(forVehicle: vehicle.id)
        #expect(readBack.count == 1)
        // The two envelope timestamps drift by one Double ulp through the
        // round trip (the epoch-offset artefact recorded in ServiceEntryTests /
        // docs/SCHEMA.md P4.11); every domain field must match exactly.
        var expected = built
        expected.createdAt = readBack[0].createdAt
        expected.updatedAt = readBack[0].updatedAt
        #expect(readBack[0] == expected)
        #expect(abs(readBack[0].createdAt.timeIntervalSinceReferenceDate
                    - built.createdAt.timeIntervalSinceReferenceDate) < 0.001)
    }

    // MARK: - Applied (the edit/reschedule path)

    @Test func appliedKeepsIdentityAndPreservesSourceEntryId() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let entryID = UUID.v7()
        let existing = Reminder(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: Self.vehicleID, title: "Insurance renewal", category: .insurance,
            dueDate: now, dueOdometer: nil, recurrence: nil,
            sourceEntryId: entryID, status: .scheduled)

        let draft = ReminderDraft(title: "Insurance renewal", category: .insurance,
                                  dueDate: now.addingTimeInterval(365 * 86_400))
        let updated = draft.applied(to: existing)

        #expect(updated.id == existing.id)
        #expect(updated.createdAt == existing.createdAt)
        #expect(updated.sourceEntryId == entryID,
                "an edit must not sever the reminder's history link")
        #expect(updated.status == .scheduled)
        #expect(updated.dueDate == now.addingTimeInterval(365 * 86_400))
    }

    @Test func appliedToTerminalRowsKeepsTheirStatus() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let draft = ReminderDraft(title: "Oil change", category: .oil, dueDate: now)
        for terminal: ReminderStatus in [.done(entryId: nil), .dismissed(reason: "sold it")] {
            let existing = Reminder(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                vehicleId: Self.vehicleID, title: "Oil change", category: .oil,
                dueDate: now, dueOdometer: nil, recurrence: nil,
                sourceEntryId: nil, status: terminal)
            let updated = draft.applied(to: existing)
            #expect(updated.status == terminal,
                    "editing history must not resurrect it into the active list")
        }
    }

    private static let vehicleID = UUID.v7()
}
