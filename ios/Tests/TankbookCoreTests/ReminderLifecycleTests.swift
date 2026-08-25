import Foundation
import Testing
@testable import TankbookCore

/// P3.4 reminder lifecycle tests (docs/SCHEMA.md -> "Reminder lifecycle
/// (normative)", docs/JOURNEYS.md J7c). The gate for this task is the full
/// transition table - scheduled/attention/done/dismissed crossed with
/// complete/reschedule/delete - because a transition the table does not cover
/// is a transition that will break in P3.5. Each transition asserts what it
/// CREATED (the next occurrence row) or PRESERVED (the old row as history),
/// never just the new status.
@Suite struct ReminderLifecycleTests {

    private static let vehicleID = UUID.v7()

    private func makeReminder(
        status: ReminderStatus = .scheduled,
        dueDate: Date? = Date(timeIntervalSince1970: 1_752_000_000),
        dueOdometer: Int? = nil,
        recurrence: Reminder.Recurrence? = nil,
        vehicleId: UUID = ReminderLifecycleTests.vehicleID,
        createdAt: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> Reminder {
        Reminder(
            id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt, deletedAt: nil,
            vehicleId: vehicleId, title: "Oil change", category: .oil,
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

    // MARK: - The full transition table (the gate)

    /// complete × {scheduled, attention, done, dismissed}.
    /// For the two active rows: status goes to `.done(entryId)`, the old row
    /// stays as history with its due fields intact, and the recurrence next
    /// occurrence is CREATED anchored at completion. For the two terminal
    /// rows: nothing happens - completing history twice must not create a
    /// second next occurrence.
    @Test func completeTransitionTable() {
        let entryID = UUID.v7()
        let completionDate = Date(timeIntervalSince1970: 1_752_200_000)
        let recurrence = Reminder.Recurrence(everyKm: 15_000, everyMonths: 12)
        let statuses: [ReminderStatus] = [
            .scheduled, .attention,
            .done(entryId: nil), .dismissed(reason: "sold the tires")
        ]

        for status in statuses {
            let reminder = makeReminder(status: status, recurrence: recurrence)
            let result = ReminderLifecycle.complete(
                reminder, entryId: entryID,
                completionDate: completionDate, completionOdometer: 118_930)

            switch status {
            case .scheduled, .attention:
                #expect(result.completed.status == .done(entryId: entryID),
                        "complete on \(status) must take the status to .done")
                // The old row stays as history, unchanged except status/stamp.
                #expect(result.completed.dueDate == reminder.dueDate,
                        "history keeps its original due")
                #expect(result.completed.dueOdometer == reminder.dueOdometer,
                        "history keeps its original due")
                #expect(result.completed.recurrence == recurrence,
                        "history keeps its recurrence")
                // The transition CREATED the next occurrence row.
                let next = result.nextOccurrence
                #expect(next != nil, "complete on \(status) must create the next row")
                #expect(next?.status == .scheduled,
                        "the next occurrence starts fresh, not carried-over done")
                #expect(next?.id != reminder.id,
                        "the next occurrence is a NEW row, never the old one")
                #expect(next?.sourceEntryId == entryID,
                        "the next row links to the completion's entry via sourceEntryId")
            case .done, .dismissed:
                #expect(result.completed == reminder,
                        "complete on terminal \(status) must be a no-op")
                #expect(result.nextOccurrence == nil,
                        "completing terminal \(status) must not fabricate a next row")
            }
        }
    }

    /// reschedule × {scheduled, attention, done, dismissed}.
    /// For the two active rows: due fields edit in place, and a fired
    /// `.attention` resets to `.scheduled` so it can notify again. For the two
    /// terminal rows: nothing - history cannot be rescheduled.
    @Test func rescheduleTransitionTable() {
        let newDate = Date(timeIntervalSince1970: 1_753_000_000)
        let statuses: [ReminderStatus] = [
            .scheduled, .attention,
            .done(entryId: nil), .dismissed(reason: "sold the tires")
        ]

        for status in statuses {
            let reminder = makeReminder(status: status,
                                        dueDate: Date(timeIntervalSince1970: 1_752_000_000),
                                        dueOdometer: 120_000)
            let rescheduled = ReminderLifecycle.reschedule(
                reminder, dueDate: newDate, dueOdometer: 125_000)

            switch status {
            case .scheduled:
                #expect(rescheduled.status == .scheduled)
                #expect(rescheduled.dueDate == newDate,
                        "reschedule edits the due date in place")
                #expect(rescheduled.dueOdometer == 125_000,
                        "reschedule edits the due odometer in place")
                #expect(rescheduled.id == reminder.id,
                        "reschedule is an in-place edit, never a new row")
            case .attention:
                #expect(rescheduled.status == .scheduled,
                        "a fired .attention resets so it can notify again")
                #expect(rescheduled.dueDate == newDate)
                #expect(rescheduled.dueOdometer == 125_000)
                #expect(rescheduled.id == reminder.id)
            case .done, .dismissed:
                #expect(rescheduled == reminder,
                        "rescheduling terminal \(status) must be a no-op")
            }
        }
    }

    /// delete × {scheduled, attention, done, dismissed}: every status
    /// tombstones - the row disappears from the live list and the tombstone
    /// survives for the 30-day undo window (restore brings it back). Distinct
    /// from `.dismissed`, tested separately below.
    @Test func deleteTransitionTable() throws {
        let statuses: [ReminderStatus] = [
            .scheduled, .attention,
            .done(entryId: nil), .dismissed(reason: "sold the tires")
        ]

        for status in statuses {
            let repo = try makeRepository()
            let vehicle = makeVehicle()
            try repo.upsertVehicle(vehicle)
            let reminder = makeReminder(status: status, vehicleId: vehicle.id)
            try repo.upsertReminder(reminder)
            try repo.softDeleteReminder(id: reminder.id)

            #expect(try repo.liveReminders(forVehicle: vehicle.id).isEmpty,
                    "a deleted \(status) reminder is gone from the live list")
            #expect(try repo.rowCount(in: TankbookSchema.reminder) == 1,
                    "the tombstone survives - it is tombstoned, not hard-deleted")

            try repo.restoreReminder(id: reminder.id)
            let restored = try repo.liveReminders(forVehicle: vehicle.id).first
            #expect(restored?.id == reminder.id,
                    "restore clears the tombstone - nothing is lost silently")
        }
    }

    // MARK: - Completion anchors at completion, not at the due date (no drift)

    /// Complete a reminder LATE and assert the next occurrence is measured from
    /// the COMPLETION date/odometer. Completing exactly on time cannot
    /// distinguish the two anchorings - a late completion is the proof.
    @Test func completionAnchorsAtCompletionNotAtDue() {
        let dueDate = Date(timeIntervalSince1970: 1_751_000_000)     // 30 days before...
        let completionDate = Date(timeIntervalSince1970: 1_753_600_000) // ...now
        let recurrence = Reminder.Recurrence(everyKm: 15_000, everyMonths: 12)

        let reminder = makeReminder(status: .attention,
                                    dueDate: dueDate,
                                    dueOdometer: 120_000,
                                    recurrence: recurrence)
        let result = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: completionDate, completionOdometer: 118_930)

        guard let next = result.nextOccurrence else {
            Issue.record("recurring completion must create the next occurrence")
            return
        }
        // Anchored at COMPLETION: completionDate + 12 months.
        let expectedDate = Calendar.current.date(byAdding: .month, value: 12,
                                                 to: completionDate)
        #expect(next.dueDate == expectedDate,
                "the next occurrence anchors at the completion date, not the original due")
        // Anchored at COMPLETION odometer: 118 930 + 15 000.
        #expect(next.dueOdometer == 133_930,
                "the next occurrence anchors at the completion odometer")
        // The due-anchored values must be WRONG for this test to be meaningful.
        #expect(next.dueDate != Calendar.current.date(byAdding: .month, value: 12, to: dueDate),
                "anchoring at the due date is exactly the drift this test proves wrong")
        #expect(next.dueOdometer != 120_000 + 15_000)
    }

    // MARK: - Declining the cost prompt still completes

    /// `.done(nil)` is a valid terminal state: completion never forces
    /// bookkeeping, and a recurring reminder still self-schedules its next
    /// occurrence (anchored at completion) even when no entry was created.
    @Test func decliningTheCostPromptStillCompletesAndRecurs() {
        let completionDate = Date(timeIntervalSince1970: 1_753_600_000)
        let recurrence = Reminder.Recurrence(everyKm: nil, everyMonths: 12)
        let reminder = makeReminder(status: .scheduled, recurrence: recurrence)

        let result = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: completionDate, completionOdometer: nil)

        #expect(result.completed.status == .done(entryId: nil),
                "declined cost log is a valid terminal state")
        #expect(result.nextOccurrence != nil,
                "a declined cost log must not break the recurrence loop")
        #expect(result.nextOccurrence?.sourceEntryId == nil,
                "no entry was created, so no sourceEntryId")
        let expectedDate = Calendar.current.date(byAdding: .month, value: 12,
                                                 to: completionDate)
        #expect(result.nextOccurrence?.dueDate == expectedDate,
                "the declined-completion next row still anchors at completion")
    }

    // MARK: - A km recurrence with a stale odometer cannot anchor the km half

    /// The ERRORS.md "stale odometer" hint: when completion carries no
    /// odometer and the recurrence is km-based, the km half cannot anchor.
    /// A date half, if present, still carries the loop; a km-only recurrence
    /// with no odometer must NOT fabricate a reminder with no due field.
    @Test func kmRecurrenceWithoutCompletionOdometerDoesNotFabricateAnUnanchoredRow() {
        let completionDate = Date(timeIntervalSince1970: 1_753_600_000)

        let kmOnly = makeReminder(status: .attention,
                                  recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: nil))
        let result = ReminderLifecycle.complete(
            kmOnly, entryId: nil, completionDate: completionDate, completionOdometer: nil)
        #expect(result.nextOccurrence == nil,
                "a km-only recurrence with no odometer has nothing to anchor on")

        let both = makeReminder(status: .attention,
                                recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        let withDate = ReminderLifecycle.complete(
            both, entryId: nil, completionDate: completionDate, completionOdometer: nil)
        #expect(withDate.nextOccurrence?.dueOdometer == nil,
                "the km half is dropped when it cannot anchor")
        let expectedDate = Calendar.current.date(byAdding: .month, value: 12,
                                                 to: completionDate)
        #expect(withDate.nextOccurrence?.dueDate == expectedDate,
                "the date half still carries the loop")
    }

    // MARK: - Dismissed is not delete

    /// `.dismissed(reason:)` keeps the row readable with its reason; a deleted
    /// reminder tombstones. The test asserts on the surviving row, never on a
    /// boolean flag.
    @Test func dismissedIsNotDelete() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)
        let reminder = makeReminder(status: .attention, vehicleId: vehicle.id)
        try repo.upsertReminder(reminder)

        let dismissed = ReminderLifecycle.dismiss(reminder, reason: "sold the tires")
        try repo.upsertReminder(dismissed)

        let live = try repo.liveReminders(forVehicle: vehicle.id)
        #expect(live.count == 1, "a dismissed reminder is NOT tombstoned")
        #expect(live[0].id == reminder.id, "the row survives")
        #expect(live[0].deletedAt == nil, "the row survives")
        #expect(live[0].status == .dismissed(reason: "sold the tires"),
                "the row and its reason stay readable")
        #expect(try repo.rowCount(in: TankbookSchema.reminder) == 1,
                "dismiss writes no tombstone - the row was not deleted")
    }

    // MARK: - Whichever comes first (date vs odometer)

    @Test func attentionIsWhicheverComesFirst() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let far = now.addingTimeInterval(120 * 86_400)   // 120 days out
        let near = now.addingTimeInterval(4 * 86_400)     // 4 days out
        let overdue = now.addingTimeInterval(-3 * 86_400) // 3 days ago

        // Date comes first: date due soon, odometer far away -> attention.
        let dateFirst = makeReminder(status: .scheduled,
                                     dueDate: near, dueOdometer: 130_000)
        #expect(ReminderLifecycle.isAttentionDue(dateFirst, currentOdometer: 118_930, now: now),
                "the near date is what fires first")
        #expect(ReminderLifecycle.derivedStatus(dateFirst, currentOdometer: 118_930, now: now) == .attention)

        // Odometer comes first: date far away, odometer within 500 km -> attention.
        let odoFirst = makeReminder(status: .scheduled,
                                    dueDate: far, dueOdometer: 119_100)
        #expect(ReminderLifecycle.isAttentionDue(odoFirst, currentOdometer: 118_930, now: now),
                "the near odometer is what fires first")
        #expect(ReminderLifecycle.derivedStatus(odoFirst, currentOdometer: 118_930, now: now) == .attention)

        // Both far -> scheduled.
        let bothFar = makeReminder(status: .scheduled,
                                   dueDate: far, dueOdometer: 130_000)
        #expect(!ReminderLifecycle.isAttentionDue(bothFar, currentOdometer: 118_930, now: now))
        #expect(ReminderLifecycle.derivedStatus(bothFar, currentOdometer: 118_930, now: now) == .scheduled)

        // Either overdue -> attention.
        let dateOverdue = makeReminder(status: .scheduled,
                                       dueDate: overdue, dueOdometer: 130_000)
        #expect(ReminderLifecycle.isAttentionDue(dateOverdue, currentOdometer: 118_930, now: now))
        let odoOverdue = makeReminder(status: .scheduled,
                                      dueDate: far, dueOdometer: 118_000)
        #expect(ReminderLifecycle.isAttentionDue(odoOverdue, currentOdometer: 118_930, now: now))

        // The boundary: exactly `attentionWindowDays` out is still attention.
        let boundaryWindow = Double(ReminderLifecycle.attentionWindowDays) * 86_400
        let boundary = makeReminder(status: .scheduled,
                                    dueDate: now.addingTimeInterval(boundaryWindow))
        #expect(ReminderLifecycle.isAttentionDue(boundary, currentOdometer: nil, now: now))
    }

    @Test func attentionRespectsTheOdometerWindowExactly() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let boundary = makeReminder(status: .scheduled, dueDate: nil,
                                    dueOdometer: 118_930 + ReminderLifecycle.attentionWindowKm)
        #expect(ReminderLifecycle.isAttentionDue(boundary, currentOdometer: 118_930, now: now),
                "exactly 500 km out is inside the window")
        let justOutside = makeReminder(status: .scheduled, dueDate: nil,
                                       dueOdometer: 118_930 + ReminderLifecycle.attentionWindowKm + 1)
        #expect(!ReminderLifecycle.isAttentionDue(justOutside, currentOdometer: 118_930, now: now))
    }

    /// An unknown current odometer cannot evaluate the km half - it is not
    /// treated as overdue, which would nag a driver about an oil change they
    /// may be nowhere near.
    @Test func unknownCurrentOdometerDoesNotFireTheKmHalf() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let kmOnly = makeReminder(status: .scheduled, dueDate: nil, dueOdometer: 120_000)
        #expect(!ReminderLifecycle.isAttentionDue(kmOnly, currentOdometer: nil, now: now),
                "without a current odometer the km half cannot fire")
        #expect(ReminderLifecycle.derivedStatus(kmOnly, currentOdometer: nil, now: now) == .scheduled)
    }

    // MARK: - The transition is stored, terminal rows never re-fire

    /// `.attention` derives at read time but the transition is STORED, and a
    /// `.done`/`.dismissed` row is never re-derived back into attention - the
    /// no-re-firing-of-past-events rule (docs/SCHEMA.md, Recalculation on
    /// edit). A stored `.attention` that has since moved out of the window
    /// derives back to `.scheduled` (reschedule is one such path).
    @Test func derivedStatusStoresAttentionAndNeverRefiresTerminalRows() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let near = now.addingTimeInterval(4 * 86_400)
        let far = now.addingTimeInterval(120 * 86_400)

        // A scheduled-but-due reminder derives to .attention (the stored
        // transition the caller persists).
        let dueSoon = makeReminder(status: .scheduled, dueDate: near)
        #expect(ReminderLifecycle.derivedStatus(dueSoon, currentOdometer: nil, now: now) == .attention)

        // A stored .attention that is no longer due derives back to .scheduled.
        let attentionButFar = makeReminder(status: .attention, dueDate: far)
        #expect(ReminderLifecycle.derivedStatus(attentionButFar, currentOdometer: nil, now: now) == .scheduled)

        // Terminal rows never re-fire, even deeply overdue.
        let done = makeReminder(status: .done(entryId: nil), dueDate: near)
        #expect(ReminderLifecycle.derivedStatus(done, currentOdometer: nil, now: now) == .done(entryId: nil))
        let dismissed = makeReminder(status: .dismissed(reason: "winter"), dueDate: near)
        let dismissedStatus = ReminderLifecycle.derivedStatus(
            dismissed, currentOdometer: nil, now: now)
        #expect(dismissedStatus == .dismissed(reason: "winter"))
        #expect(!ReminderLifecycle.isAttentionDue(done, currentOdometer: nil, now: now))
        #expect(!ReminderLifecycle.isAttentionDue(dismissed, currentOdometer: nil, now: now))
    }

    // MARK: - The edit/reschedule path through the draft

    @Test func draftAppliedToAttentionResetsItAndKeepsIdentity() {
        let reminder = makeReminder(status: .attention,
                                    dueDate: Date(timeIntervalSince1970: 1_751_000_000),
                                    dueOdometer: 120_000)
        let newDate = Date(timeIntervalSince1970: 1_753_000_000)
        let draft = ReminderDraft(title: "Oil change", category: .oil,
                                  dueDate: newDate, dueOdometer: 125_000,
                                  recurrenceEveryKm: 15_000, recurrenceEveryMonths: 12)

        let updated = draft.applied(to: reminder)

        #expect(updated.id == reminder.id, "edit is an in-place update")
        #expect(updated.createdAt == reminder.createdAt, "creation stamp survives edits")
        #expect(updated.status == .scheduled,
                "editing a fired .attention resets it so it can notify again")
        #expect(updated.dueDate == newDate)
        #expect(updated.dueOdometer == 125_000)
        #expect(updated.recurrence?.everyKm == 15_000)
        #expect(updated.recurrence?.everyMonths == 12)
    }

    // MARK: - Date arithmetic

    @Test func daysRemainingIsWholeDaysFromStartOfDay() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let twelveDays = now.addingTimeInterval(12 * 86_400)
        #expect(ReminderLifecycle.daysRemaining(until: twelveDays, from: now) == 12)
        let overdue = now.addingTimeInterval(-3 * 86_400)
        #expect(ReminderLifecycle.daysRemaining(until: overdue, from: now) == -3)
        #expect(ReminderLifecycle.daysRemaining(until: now, from: now) == 0)
    }
}
