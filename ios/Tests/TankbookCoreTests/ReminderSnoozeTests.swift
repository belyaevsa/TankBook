import Foundation
import Testing
@testable import TankbookCore

/// RV.78 snooze transition tests (docs/NOTIFICATIONS.md -> the actions,
/// docs/SCHEMA.md -> Reminder lifecycle). Kept out of `ReminderLifecycleTests`
/// so neither suite outgrows its lint budget. The banner's "Push a week" is a
/// RESCHEDULE with a defined defer, and these pin the defer:
///
/// 1. the due date moves forward exactly `ReminderLifecycle.snoozeDays`;
/// 2. a fired `.attention` resets to `.scheduled` so the planner can re-arm;
/// 3. an odometer-only reminder has no date half to push - the threshold is
///    untouched (no guessed weekly distance, hard rule 13);
/// 4. snooze is literally `reschedule(due + 7)` - the same transition the
///    Reminders form edits with, never a second implementation;
/// 5. terminal rows (history) are untouched.
@Suite struct ReminderSnoozeTests {

    private static let vehicleID = UUID.v7()

    private func makeReminder(status: ReminderStatus = .attention,
                              dueDate: Date? = Date(timeIntervalSince1970: 1_752_000_000),
                              dueOdometer: Int? = nil) -> Reminder {
        Reminder(
            id: UUID.v7(), createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000), deletedAt: nil,
            vehicleId: ReminderSnoozeTests.vehicleID, title: "Oil change", category: .oil,
            dueDate: dueDate, dueOdometer: dueOdometer,
            recurrence: nil, sourceEntryId: nil, status: status)
    }

    /// snooze × {scheduled, attention, done, dismissed}: for the two active
    /// rows the due date moves forward exactly `snoozeDays`, in place (same
    /// id), and a fired `.attention` resets to `.scheduled` so the planner
    /// re-arms. Terminal rows come back unchanged - history cannot be pushed.
    @Test func snoozeTransitionTable() {
        let baseDate = Date(timeIntervalSince1970: 1_752_000_000)
        let statuses: [ReminderStatus] = [
            .scheduled, .attention,
            .done(entryId: nil), .dismissed(reason: "sold the tires")
        ]

        for status in statuses {
            let reminder = makeReminder(status: status,
                                        dueDate: baseDate,
                                        dueOdometer: 120_000)
            let snoozed = ReminderLifecycle.snooze(reminder, now: baseDate)

            switch status {
            case .scheduled:
                #expect(snoozed.status == .scheduled)
            case .attention:
                #expect(snoozed.status == .scheduled,
                        "snoozing a fired .attention resets it so it can notify again")
            case .done, .dismissed:
                #expect(snoozed == reminder,
                        "snoozing terminal \(status) must be a no-op")
                continue
            }
            #expect(snoozed.id == reminder.id, "snooze is an in-place edit, never a new row")
            let expectedDate = Calendar.current.date(
                byAdding: .day, value: ReminderLifecycle.snoozeDays, to: baseDate)
            #expect(snoozed.dueDate == expectedDate,
                    "snooze defers the due date by exactly \(ReminderLifecycle.snoozeDays) days")
            #expect(snoozed.dueOdometer == 120_000,
                    "snooze leaves the odometer half untouched")
        }
    }

    /// A reminder due only by odometer has no date half to push - snooze keeps
    /// the threshold and resets a fired `.attention`, so the odometer rule (not
    /// a guessed weekly distance) decides when it is next due.
    @Test func snoozingAnOdometerOnlyReminderKeepsItsThreshold() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let reminder = makeReminder(status: .attention, dueDate: nil, dueOdometer: 120_000)
        let snoozed = ReminderLifecycle.snooze(reminder, now: now)

        #expect(snoozed.status == .scheduled, "the fired state resets")
        #expect(snoozed.dueOdometer == 120_000,
                "a week is a time span; the km threshold is not moved by a guessed weekly distance")
        #expect(snoozed.dueDate == nil)
    }

    /// Snooze is a RESCHEDULE with a defined defer - the same transition the
    /// Reminders form edits through, never a second implementation (RV.78's
    /// one-code-path rule). A snoozed reminder equals reschedule(due + 7).
    @Test func snoozeIsRescheduleWithTheSnoozeDelta() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let reminder = makeReminder(status: .attention,
                                    dueDate: now,
                                    dueOdometer: 120_000)
        let snoozed = ReminderLifecycle.snooze(reminder, now: now)
        let pushedDate = Calendar.current.date(
            byAdding: .day, value: ReminderLifecycle.snoozeDays, to: now)
        let manual = ReminderLifecycle.reschedule(
            reminder, dueDate: pushedDate, dueOdometer: 120_000, now: now)
        #expect(snoozed == manual,
                "snooze and the form's reschedule must produce the same row")
    }
}
