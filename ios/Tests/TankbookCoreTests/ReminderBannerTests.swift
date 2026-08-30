import Foundation
import Testing
@testable import TankbookCore

/// PJ.4: the Home banner's reminder selection. The banner is REAL data - it
/// derives from the live reminders via `ReminderLifecycle.derivedStatus`, never
/// from a stored flag or a launch argument. These tests pin the derivation:
/// presence = some active reminder is attention-due, the subject is the
/// earliest one, and a completed reminder drops the banner by construction
/// (terminal rows never re-derive, docs/SCHEMA.md).
@Suite struct ReminderBannerTests {

    private static let vehicleID = UUID.v7()

    /// `now` anchored mid-day so the day-anchored counts in the fixtures are
    /// exact regardless of the test runner's clock time.
    private let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 3, day: 10, hour: 14))!

    private func makeReminder(
        title: String = "Insurance renewal",
        dueDate: Date?,
        dueOdometer: Int? = nil,
        status: ReminderStatus = .scheduled,
        createdAt: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> Reminder {
        Reminder(
            id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt, deletedAt: nil,
            vehicleId: ReminderBannerTests.vehicleID, title: title, category: .insurance,
            dueDate: dueDate, dueOdometer: dueOdometer,
            recurrence: nil, sourceEntryId: nil, status: status)
    }

    private func days(_ value: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: value, to: now) ?? now
    }

    // MARK: - Presence is derived, never stored

    /// No active reminder inside the attention window - the banner has nothing
    /// to say. This is the common path: a user with only scheduled reminders
    /// far out sees no banner at all.
    @Test func noAttentionDueReminderShowsNoBanner() {
        let far = makeReminder(dueDate: days(60))
        #expect(ReminderBanner.bannerReminder(
            among: [far], currentOdometer: nil, now: now) == nil)
    }

    /// A reminder exactly at the attention-window edge (12 days) is due; 13
    /// days is not - the window boundary is part of the derivation.
    @Test func attentionWindowBoundaryIsRespected() {
        let atEdge = makeReminder(dueDate: days(12))
        #expect(ReminderBanner.bannerReminder(
            among: [atEdge], currentOdometer: nil, now: now) == atEdge)
        let outside = makeReminder(dueDate: days(13))
        #expect(ReminderBanner.bannerReminder(
            among: [outside], currentOdometer: nil, now: now) == nil)
    }

    /// An overdue reminder is still attention-due (docs/SCHEMA.md: "already
    /// overdue demands attention") - the banner must keep announcing it, not
    /// silently drop a due task.
    @Test func overdueReminderStillShows() {
        let overdue = makeReminder(dueDate: days(-4))
        #expect(ReminderBanner.bannerReminder(
            among: [overdue], currentOdometer: nil, now: now) == overdue)
    }

    /// An odometer reminder inside its km window is due too - the date and
    /// odometer halves are independent attention drivers.
    @Test func odometerReminderInsideWindowShows() {
        let odometer = makeReminder(dueDate: nil, dueOdometer: 118_500)
        #expect(ReminderBanner.bannerReminder(
            among: [odometer], currentOdometer: 118_000, now: now) == odometer)
        let far = makeReminder(dueDate: nil, dueOdometer: 120_000)
        #expect(ReminderBanner.bannerReminder(
            among: [far], currentOdometer: 118_000, now: now) == nil)
    }

    // MARK: - The subject is the earliest due

    /// Several reminders are due at once: the banner names the earliest one -
    /// the same ordering as the list's attention group.
    @Test func earliestAttentionDueReminderIsChosen() {
        let inTwo = makeReminder(title: "Inspection", dueDate: days(2),
                                 createdAt: Date(timeIntervalSince1970: 1_751_000_000))
        let inNine = makeReminder(title: "Oil change", dueDate: days(9))
        let inThree = makeReminder(title: "Winter tires", dueDate: days(3))
        let chosen = ReminderBanner.bannerReminder(
            among: [inNine, inThree, inTwo], currentOdometer: nil, now: now)
        #expect(chosen?.title == "Inspection")
    }

    /// A tie on the due point resolves by the older `createdAt`, exactly like
    /// the list's sort (deterministic, no hash-seed dependence).
    @Test func tieBreaksByTheOlderCreatedAt() {
        let older = makeReminder(dueDate: days(5),
                                 createdAt: Date(timeIntervalSince1970: 1_749_000_000))
        let newer = makeReminder(dueDate: days(5),
                                 createdAt: Date(timeIntervalSince1970: 1_751_000_000))
        let chosen = ReminderBanner.bannerReminder(
            among: [newer, older], currentOdometer: nil, now: now)
        #expect(chosen == older)
    }

    // MARK: - It changes when a reminder completes (no stored flag)

    /// The banner's whole point: completing a reminder must retire it. The
    /// completion transition writes `.done(entryId)`; terminal rows never
    /// re-derive, so the same derivation that showed the banner now hides it.
    /// No flag is stored anywhere - the status IS the state.
    @Test func bannerGoesAwayWhenTheReminderCompletes() {
        let reminder = makeReminder(dueDate: days(3))
        #expect(ReminderBanner.bannerReminder(
            among: [reminder], currentOdometer: nil, now: now) == reminder)

        let result = ReminderLifecycle.complete(
            reminder, entryId: nil,
            completionDate: now, completionOdometer: nil, now: now)
        #expect(result.completed.status == .done(entryId: nil))
        #expect(ReminderBanner.bannerReminder(
            among: [result.completed], currentOdometer: nil, now: now) == nil)
    }

    /// Dismissing is the other terminal exit: a dismissed-with-reason row is
    /// history, not an announcement.
    @Test func dismissedReminderNeverShows() {
        let dismissed = ReminderLifecycle.dismiss(
            makeReminder(dueDate: days(1)), reason: "sold the tires", now: now)
        #expect(ReminderBanner.bannerReminder(
            among: [dismissed], currentOdometer: nil, now: now) == nil)
    }

    /// The banner reads the LIVE rows: after a reschedule that pushed the due
    /// date out of the window, the banner retires itself - the state is
    /// re-derived on every read, never cached.
    @Test func rescheduleOutOfWindowRetiresTheBanner() {
        let reminder = makeReminder(dueDate: days(2))
        #expect(ReminderBanner.bannerReminder(
            among: [reminder], currentOdometer: nil, now: now) == reminder)
        let rescheduled = ReminderLifecycle.reschedule(
            reminder, dueDate: days(90), dueOdometer: nil, now: now)
        #expect(ReminderBanner.bannerReminder(
            among: [rescheduled], currentOdometer: nil, now: now) == nil)
    }

    /// With the km half unknown (no current odometer), an odometer reminder's
    /// attention cannot be evaluated and it must not fabricate a due state.
    @Test func odometerReminderWithNoCurrentOdometerShowsNothing() {
        let odometer = makeReminder(dueDate: nil, dueOdometer: 118_500)
        #expect(ReminderBanner.bannerReminder(
            among: [odometer], currentOdometer: nil, now: now) == nil)
    }
}
