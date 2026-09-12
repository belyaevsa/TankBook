import TankbookCore
import XCTest
@testable import Tankbook

/// RV.240 + RV.268 - the J9 anomaly card's two owner decisions of 2026-09-12.
///
/// RV.240: *Dismiss* is one tap that suppresses the cause. The dismissal no
/// longer carries a reason - the field, the sheet that collected it and its
/// copy are gone, so there is nothing to read back. This test pins the stored
/// shape: a dismissal round-trips by `AnomalyCause` alone.
///
/// RV.268: the *act* reminder is due at the shared default, one year out, not
/// today. `HomeView.actReminder` is the pure seam the act persists, so the
/// due-date decision is L1-testable without a simulator.
@MainActor
final class RV240RV268AnomalyCardTests: XCTestCase {

    // MARK: - RV.240: a dismissal stores the cause, never a reason

    func testDismissalRoundTripsByCauseAlone() throws {
        let vehicleID = UUID.v7()
        let key = "anomalyInsight.dismissals.\(vehicleID.uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let cause = AnomalyCause(metric: .consumption, evaluatedYear: 2026, evaluatedMonth: 9)
        AnomalyInsightStore.record(AnomalyDismissal(cause: cause, dismissedAt: Date()),
                                   for: vehicleID)

        let stored = AnomalyInsightStore.dismissals(for: vehicleID)
        XCTAssertEqual(stored.count, 1, "the store must remember exactly the dismissal")
        XCTAssertTrue(stored.contains(where: { $0.cause == cause }),
                      "the dismissed cause must be stored")
    }

    // MARK: - RV.268: the act reminder's due date

    func testActReminderIsDueAtTheSharedDefaultNotToday() throws {
        let now = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let reminder = HomeView.actReminder(vehicleId: UUID.v7(),
                                            title: "Check fuel consumption", now: now)

        let expected = ReminderLifecycle.defaultDueDate(from: now)
        XCTAssertEqual(reminder.dueDate, expected,
                       "the act reminder must use the shared default due date")
        XCTAssertFalse(Calendar.current.isDate(reminder.dueDate ?? now, inSameDayAs: now),
                       "the act reminder must not be due today")
        XCTAssertEqual(reminder.category, .custom)
        XCTAssertEqual(reminder.title, "Check fuel consumption")
    }

    func testSharedDefaultDueDateIsOneYearOut() throws {
        let now = try XCTUnwrap(ConfirmDate.parse("10.08.2026"))
        let due = ReminderLifecycle.defaultDueDate(from: now)
        let oneYear = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: 1, to: now))
        XCTAssertEqual(due, oneYear, "the shared default is one year out")
    }
}
