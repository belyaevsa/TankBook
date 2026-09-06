import XCTest
import UserNotifications
@testable import Tankbook

/// RV.78 L2 tests (docs/TESTING.md L2) - the fired-reminder banner actions
/// against the REAL `UNUserNotificationCenter`, run inside the app process
/// (the `TankbookTests` host, the FileProtectionTests pattern). The category
/// registration and the scheduled requests are platform facts; asserting them
/// through the real center is what makes them facts rather than code that
/// compiles.
///
/// Vacuous traps this suite is built against:
/// - asserting the category is *registered* without any response having been
///   exercised (L4 replays the responses; L4 alone would leave registration
///   unproven and attach unproven - hence these);
/// - a snooze that moves the due date but never re-arms;
/// - a request that never carries the category (registered but not attached);
/// - a completion that leaves its notification armed.
@MainActor
final class ReminderNotificationActionTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    override func tearDownWithError() throws {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Registration at launch

    /// The category is registered at LAUNCH with both actions. The test host is
    /// the app itself, so by the time the test body runs, `AppRootView.init`
    /// has ensured the delegate and registered the category. Polling guards the
    /// first-frame edge; the assertion is against the real registered set,
    /// never a constant.
    func testReminderCategoryIsRegisteredAtLaunchWithBothActions() async throws {
        var categories: Set<UNNotificationCategory> = []
        for _ in 0..<50 {
            categories = await UNUserNotificationCenter.current().notificationCategories()
            if categories.contains(where: { $0.identifier == "reminder.actions" }) { break }
            try await Task.sleep(for: .milliseconds(200))
        }

        let category = try XCTUnwrap(
            categories.first { $0.identifier == "reminder.actions" },
            "the fired-reminder category must be registered at launch")
        let actionIDs = Set(category.actions.map(\.identifier))
        XCTAssertEqual(actionIDs,
                       ["reminder.action.complete", "reminder.action.snooze"],
                       "the category must carry exactly the two banner actions")
        for action in category.actions {
            XCTAssertFalse(action.title.isEmpty,
                           "an action must carry a localised title")
        }
    }

    // MARK: - Snooze re-arms; the armed request carries the category

    /// Responding with **Push a week** defers the fired reminder and RE-ARMS it:
    /// after the coordinator's snooze path, a pending date request exists for
    /// the reminder on the real center. This is the assertion that fails if
    /// snooze only edits the row and never schedules (mutation 2). The same
    /// request must carry the actions category - the assertion that fails if
    /// the category is registered but never attached to scheduled requests
    /// (mutation 3).
    func testSnoozeResponseReArmsAndTheArmedRequestCarriesTheCategory() async throws {
        let reminderID = ReminderNotificationActionTestSupport.seedFiredDateReminder(dueInDays: 11)
        let coordinator = ReminderNotificationCoordinator()

        await coordinator.snooze(reminderID: reminderID)

        let identifier = "reminder.\(reminderID.uuidString).date"
        let pending = try await waitForPending(identifier: identifier, timeout: 5)
        XCTAssertEqual(pending, identifier,
                       "snooze must re-arm the fired date notification for the new due")

        let category = await ReminderNotificationActionTestSupport
            .categoryIdentifier(for: identifier)
        XCTAssertEqual(category, "reminder.actions",
                       "a scheduled reminder request must carry the actions category")
    }

    /// Snoozing an id no reminder answers mutates nothing and arms nothing - a
    /// stale notification is inert (hard rule 7), never a crash and never a
    /// stray request.
    func testSnoozingAnUnknownReminderArmsNothing() async throws {
        let coordinator = ReminderNotificationCoordinator()
        await coordinator.snooze(reminderID: UUID())

        let pending = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
        XCTAssertTrue(pending.isEmpty,
                      "snoozing an unresolvable reminder must arm nothing")
    }

    // MARK: - Completing disarms

    /// A completed reminder must not leave its notification armed. Arm a fired
    /// reminder deterministically (snooze re-arms it ~6 days out), then complete
    /// it through the exact code path the completion sheet uses; the pending
    /// request must be gone. This fails if completion marks `.done` but never
    /// cancels (the "armed after complete" trap).
    func testCompletingThroughTheSheetPathDisarmsThePendingNotification() async throws {
        let reminderID = ReminderNotificationActionTestSupport.seedFiredDateReminder(dueInDays: 11)
        let coordinator = ReminderNotificationCoordinator()
        await coordinator.snooze(reminderID: reminderID)
        let identifier = "reminder.\(reminderID.uuidString).date"
        let armed = try await waitForPending(identifier: identifier, timeout: 5)
        XCTAssertEqual(armed, identifier,
                       "precondition: the reminder must be armed before completion")

        ReminderNotificationActionTestSupport.completeAsTheSheetDoes(reminderID: reminderID,
                                                                     coordinator: coordinator)

        // The sheet's completion path reconciles in a Task; poll for the cancel
        // to land on the real center rather than racing it.
        let leftover = try await waitForNoPending(reminderID: reminderID, timeout: 5)
        XCTAssertTrue(leftover.isEmpty,
                      "a completed reminder must not leave its notification armed; still pending: \(leftover)")
    }

    // MARK: - Helpers

    private func waitForPending(identifier: String, timeout: TimeInterval) async throws -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let pending = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
            if let match = pending.first(where: { $0 == identifier }) {
                return match
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    private func waitForNoPending(reminderID: UUID, timeout: TimeInterval) async throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let pending = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
            let leftover = pending.filter { $0.hasPrefix("reminder.\(reminderID.uuidString).") }
            if leftover.isEmpty { return [] }
            try await Task.sleep(for: .milliseconds(200))
        }
        let final = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
        return final.filter { $0.hasPrefix("reminder.\(reminderID.uuidString).") }
    }
}
