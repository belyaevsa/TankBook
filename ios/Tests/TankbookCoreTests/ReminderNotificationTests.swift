import Foundation
import Testing
@testable import TankbookCore

/// P3.6 local-notification tests (docs/NOTIFICATIONS.md). The plan is the whole
/// decision layer, so these assert its OUTPUT - dates, identifiers, bodies -
/// never a `UNUserNotificationCenter` call (which cannot be asserted against).
/// Four rules the tests exist to pin:
/// 1. an odometer threshold is crossed by a SAVE, and the save arms (write-time
///    arming), the fire time being the next humane hour;
/// 2. every scheduled time is 09:00 or 10:00 local (humane hours, never night);
/// 3. exactly one overdue follow-up, never a nag loop - tested as a loop;
/// 4. complete / reschedule / dismiss / delete each cancel the reminder's
///    pending notification everywhere.
@Suite struct ReminderNotificationTests {

    private static let vehicleID = UUID.v7()

    /// A fixed calendar so fire dates are deterministic regardless of the test
    /// host's timezone (humane hours are asserted as components, not strings,
    /// but the components are only meaningful against a known calendar).
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeReminder(
        title: String = "Oil change",
        category: ReminderCategory = .oil,
        status: ReminderStatus = .scheduled,
        dueDate: Date? = Date(timeIntervalSince1970: 1_752_000_000),
        dueOdometer: Int? = nil,
        vehicleId: UUID = ReminderNotificationTests.vehicleID
    ) -> Reminder {
        Reminder(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            vehicleId: vehicleId, title: title, category: category,
            dueDate: dueDate, dueOdometer: dueOdometer,
            recurrence: nil, sourceEntryId: nil, status: status)
    }

    private func plan(_ reminders: [Reminder],
                      now: Date,
                      odometer: Int?) -> ReminderNotificationPlan {
        ReminderNotificationPlanner.plan(reminders: reminders,
                                         now: now,
                                         currentOdometer: odometer,
                                         calendar: Self.calendar)
    }

    // MARK: - 1. Threshold crossing arms (write time)

    /// A save that takes the odometer inside a reminder's `dueOdometer` window
    /// produces a scheduled odometer notification; a save that leaves it outside
    /// produces none. The boundary is asserted on BOTH sides (exactly 500 km is
    /// inside, 501 is outside - docs/NOTIFICATIONS.md "within 500 km").
    @Test func odometerCrossingArmsAndNonCrossingDoesNot() {
        let now = date(2025, 6, 1, 15, 30)
        let current = 118_930

        let atBoundary = makeReminder(dueDate: nil, dueOdometer: current + 500)
        let boundaryPlan = plan([atBoundary], now: now, odometer: current)
        #expect(boundaryPlan.scheduled.contains {
            $0.kind == .odometer && $0.reminderId == atBoundary.id
        }, "exactly 500 km out is inside the window and arms")

        let outside = makeReminder(dueDate: nil, dueOdometer: current + 501)
        let outsidePlan = plan([outside], now: now, odometer: current)
        #expect(!outsidePlan.scheduled.contains { $0.kind == .odometer },
                "501 km out does not arm")

        // An unknown current odometer cannot evaluate the km half (the same
        // rule as the attention derivation - a driver we cannot place is not
        // nagged).
        let unknownPlan = plan([atBoundary], now: now, odometer: nil)
        #expect(!unknownPlan.scheduled.contains { $0.kind == .odometer })
    }

    /// The odometer notification fires the day after the save, at the odometer
    /// humane hour - armed at write time, never "at the due moment".
    @Test func odometerNotificationFiresTheDayAfterTheSave() {
        let now = date(2025, 6, 1, 15, 30)
        let reminder = makeReminder(dueDate: nil, dueOdometer: 119_000)
        let plan = self.plan([reminder], now: now, odometer: 118_930)

        let fire = plan.scheduled.first { $0.kind == .odometer }!
        #expect(fire.fireDate == date(2025, 6, 2, ReminderNotificationPlanner.odometerHour, 0),
                "armed at write time, fires the next humane morning")
    }

    // MARK: - 2. Humane hours

    /// Every scheduled time is 09:00 or 10:00 local, asserted as components
    /// (never a formatted string). Includes a reminder due at 23:30 - the case
    /// that catches "schedule at the due moment".
    @Test func everyScheduledTimeIsAHumaneHour() {
        let now = date(2025, 6, 1, 12, 0)
        let reminders = [
            makeReminder(title: "Insurance", dueDate: date(2025, 7, 1, 23, 30), dueOdometer: nil),
            makeReminder(title: "Oil", dueDate: nil, dueOdometer: 119_000),
            makeReminder(title: "TUV", dueDate: date(2025, 5, 1), dueOdometer: nil)
        ]
        let plan = self.plan(reminders, now: now, odometer: 118_930)

        #expect(!plan.scheduled.isEmpty)
        for notification in plan.scheduled {
            let components = Self.calendar.dateComponents([.hour, .minute], from: notification.fireDate)
            #expect(components.hour == ReminderNotificationPlanner.dateHour
                        || components.hour == ReminderNotificationPlanner.odometerHour,
                    "a fire time must be 09:00 or 10:00, was \(components.hour ?? -1)")
            #expect(components.minute == 0)
        }

        // The date reminder's fire time is the window start (09:00), not the
        // 23:30 its due date carries.
        let dateFire = plan.scheduled.first { $0.kind == .date }!
        #expect(Self.calendar.component(.hour, from: dateFire.fireDate)
                    == ReminderNotificationPlanner.dateHour)
    }

    /// The date notification lands at 09:00 on `dueDate - 12 days` - the
    /// due-window start, with the due date's time-of-day discarded.
    @Test func dateNotificationFiresAtTheWindowStart() {
        let now = date(2025, 6, 1, 12, 0)
        let reminder = makeReminder(dueDate: date(2025, 7, 1, 23, 30), dueOdometer: nil)
        let plan = self.plan([reminder], now: now, odometer: nil)

        let fire = plan.scheduled.first { $0.kind == .date }!
        #expect(fire.fireDate == date(2025, 6, 19, 9, 0),
                "12 days before the due date, at 09:00 - not the 23:30 due moment")
    }

    // MARK: - 3. Exactly one overdue follow-up (tested as a loop)

    /// The never-a-nag-loop rule as a loop: at due + 7, + 14 and + 21 days the
    /// plan still holds exactly one overdue entry for the reminder, never one
    /// per day and never zero-and-re-scheduled. The fire date stays `due + 7`;
    /// the adapter's `pending` drops it once it is past.
    @Test func overdueFollowUpIsExactlyOneRegardlessOfHowOverdue() {
        let reminder = makeReminder(dueDate: date(2025, 5, 1), dueOdometer: nil)
        let horizons = [date(2025, 5, 8, 12, 0),
                        date(2025, 5, 15, 12, 0),
                        date(2025, 5, 22, 12, 0)]

        for now in horizons {
            let plan = self.plan([reminder], now: now, odometer: nil)
            let overdue = plan.scheduled.filter { $0.kind == .overdue }
            #expect(overdue.count == 1, "at \(now) expected exactly one overdue entry, got \(overdue.count)")
            #expect(overdue.first?.fireDate == date(2025, 5, 8, 9, 0),
                    "the follow-up stays anchored at due + 7 days, never drifts")
        }
    }

    /// A reminder that is NOT overdue has no overdue follow-up.
    @Test func notYetOverdueHasNoFollowUp() {
        let reminder = makeReminder(dueDate: date(2025, 7, 1), dueOdometer: nil)
        let plan = self.plan([reminder], now: date(2025, 6, 1), odometer: nil)
        #expect(!plan.scheduled.contains { $0.kind == .overdue })
    }

    // MARK: - 4. Resolution cancels (four cases)

    @Test func completingCancelsEveryNotification() {
        let reminder = makeReminder(status: .attention,
                                    dueDate: date(2025, 7, 1),
                                    dueOdometer: 120_000)
        let completed = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: date(2025, 6, 1), completionOdometer: 118_930).completed
        let plan = self.plan([completed], now: date(2025, 6, 1), odometer: 118_930)

        #expect(plan.scheduled.isEmpty, "a completed reminder schedules nothing")
        #expect(plan.cancelled == Set(ReminderNotificationPlanner.identifiers(for: reminder)),
                "completion cancels every identifier the reminder owned")
    }

    @Test func dismissingCancelsEveryNotification() {
        let reminder = makeReminder(status: .attention,
                                    dueDate: date(2025, 7, 1),
                                    dueOdometer: 120_000)
        let dismissed = ReminderLifecycle.dismiss(reminder, reason: "sold the tires")
        let plan = self.plan([dismissed], now: date(2025, 6, 1), odometer: 118_930)

        #expect(plan.scheduled.isEmpty)
        #expect(plan.cancelled == Set(ReminderNotificationPlanner.identifiers(for: reminder)))
    }

    /// A reschedule that removes a due field cancels that field's notification
    /// (here: the odometer half), while the surviving date half is re-scheduled.
    @Test func reschedulingCancelsTheSupersededNotification() {
        let reminder = makeReminder(status: .attention,
                                    dueDate: date(2025, 7, 1),
                                    dueOdometer: 120_000)
        let rescheduled = ReminderLifecycle.reschedule(
            reminder, dueDate: date(2026, 1, 1), dueOdometer: nil)
        let plan = self.plan([rescheduled], now: date(2025, 6, 1), odometer: 118_930)

        #expect(plan.cancelled.contains(ReminderNotificationPlanner.identifier(.odometer, for: reminder)),
                "removing the odometer field cancels the odometer notification")
        #expect(plan.scheduled.contains { $0.kind == .date },
                "the surviving date half is still scheduled")
        #expect(!plan.scheduled.contains { $0.kind == .odometer })
    }

    /// Deletion tombstones the row out of `liveReminders`, so the plan cannot
    /// see it - the delete site cancels via `identifiers(for:)`. The test pins
    /// that this returns exactly the three stable identifiers.
    @Test func deletingCancelsEveryKind() {
        let reminder = makeReminder(dueDate: date(2025, 7, 1), dueOdometer: 120_000)
        let ids = Set(ReminderNotificationPlanner.identifiers(for: reminder))

        #expect(ids.count == 3, "a reminder owns exactly three identifiers")
        #expect(ids.contains(ReminderNotificationPlanner.identifier(.date, for: reminder)))
        #expect(ids.contains(ReminderNotificationPlanner.identifier(.odometer, for: reminder)))
        #expect(ids.contains(ReminderNotificationPlanner.identifier(.overdue, for: reminder)))
    }

    // MARK: - 5. Rescheduling re-arms

    /// A fired `.attention` is already armed (it does not re-arm on every
    /// recompute); rescheduling resets it to `.scheduled` and moves the due out,
    /// so a later crossing arms again - the P3.4 "can notify again" rule.
    @Test func rescheduledAttentionCanArmAgain() {
        let now = date(2025, 6, 1, 12, 0)
        let current = 118_930

        // Fired: the odometer crossed and the notification is armed - stored
        // `.attention` means the plan does not produce a second one.
        let fired = makeReminder(status: .attention, dueDate: nil, dueOdometer: 119_400)
        let firedPlan = self.plan([fired], now: now, odometer: current)
        #expect(!firedPlan.scheduled.contains { $0.kind == .odometer },
                "a stored .attention has already armed and must not re-arm")

        // Reschedule resets to .scheduled and moves the due out of the window.
        let rescheduled = ReminderLifecycle.reschedule(fired, dueDate: nil, dueOdometer: 125_000)
        #expect(rescheduled.status == .scheduled, "reschedule resets a fired .attention")
        let outOfWindow = self.plan([rescheduled], now: now, odometer: current)
        #expect(!outOfWindow.scheduled.contains { $0.kind == .odometer })

        // The driver crosses the new threshold: still .scheduled, within 500 km
        // of the new due - arms again.
        let crossedAgain = self.plan([rescheduled], now: now, odometer: 124_600)
        #expect(crossedAgain.scheduled.contains { $0.kind == .odometer },
                "a rescheduled reminder can notify again once crossed")
    }

    // MARK: - Materialization (never a nag)

    /// The adapter schedules only the future subset: a past fire date means the
    /// notification already fired and re-scheduling it would re-open the nag
    /// loop the overdue rule exists to forbid.
    @Test func pendingDropsPastFireDates() {
        let now = date(2025, 6, 1, 12, 0)
        let past = ReminderNotification(reminderId: UUID.v7(), kind: .overdue,
                                        fireDate: date(2025, 5, 8, 9, 0),
                                        body: .overdue(title: "Insurance"))
        let future = ReminderNotification(reminderId: UUID.v7(), kind: .date,
                                          fireDate: date(2025, 6, 19, 9, 0),
                                          body: .dateDue(title: "Oil", days: 12))
        let result = ReminderNotificationPlanner.pending([past, future], at: now)
        #expect(result == [future])
    }

    // MARK: - 6. Permission policy

    /// Requested at the first reminder creation, never at launch, never after a
    /// denial (a denied state is only ever answered from Settings).
    @Test func permissionRequestedAtFirstReminderNotAtLaunch() {
        // Launch with no reminders: never request.
        #expect(!NotificationPermissionGate.shouldRequest(
            authorization: .notDetermined, hasActiveReminders: false, didRequestThisLaunch: false))
        // First reminder creation: request.
        #expect(NotificationPermissionGate.shouldRequest(
            authorization: .notDetermined, hasActiveReminders: true, didRequestThisLaunch: false))
        // Same launch, another reminder: no repeat request.
        #expect(!NotificationPermissionGate.shouldRequest(
            authorization: .notDetermined, hasActiveReminders: true, didRequestThisLaunch: true))
        // Denied: never re-request (no nag loop).
        #expect(!NotificationPermissionGate.shouldRequest(
            authorization: .denied, hasActiveReminders: true, didRequestThisLaunch: false))
        // Authorized: nothing to ask.
        #expect(!NotificationPermissionGate.shouldRequest(
            authorization: .authorized, hasActiveReminders: true, didRequestThisLaunch: false))
    }

    /// The denied card shows once, only while denied with reminders present, and
    /// never again after it has been handled.
    @Test func deniedCardShowsOnce() {
        #expect(NotificationPermissionGate.shouldShowDeniedCard(
            authorization: .denied, hasActiveReminders: true, cardAlreadyHandled: false))
        #expect(!NotificationPermissionGate.shouldShowDeniedCard(
            authorization: .denied, hasActiveReminders: true, cardAlreadyHandled: true),
                "once handled, the card never returns - no nag loop")
        #expect(!NotificationPermissionGate.shouldShowDeniedCard(
            authorization: .notDetermined, hasActiveReminders: true, cardAlreadyHandled: false))
        #expect(!NotificationPermissionGate.shouldShowDeniedCard(
            authorization: .authorized, hasActiveReminders: true, cardAlreadyHandled: false))
        #expect(!NotificationPermissionGate.shouldShowDeniedCard(
            authorization: .denied, hasActiveReminders: false, cardAlreadyHandled: false),
                "no reminders, no card - nothing is notification-gated")
    }
}
