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

    // MARK: - RV.81 archiving strips, unarchiving re-arms

    /// Archiving a car must cancel EVERY pending reminder request that car
    /// owns while leaving another car's requests armed. The first half is the
    /// assertion that fails if archiving cancels nothing (mutation 1's other
    /// side); the second half is the one that fails if the archive cancels
    /// EVERYTHING on the center (over-cancel). The archived car carries TWO
    /// armed reminders so "every request for that car" means more than one.
    /// Drives the real coordinator reconcile over the real center - the exact
    /// path `VehicleDetailView.toggleArchive` runs after the repository write.
    func testArchivingCancelsThatCarsRequestsAndLeavesAnotherCarsArmed() async throws {
        let coordinator = ReminderNotificationCoordinator()

        // Car A: two reminders. Car B: one. Both far-future so each reconcile
        // arms a deterministic date notification at due - 12 days.
        let carA = ReminderNotificationActionTestSupport.seedScheduledReminder(dueInDays: 120)
        let carAextra = ReminderNotificationActionTestSupport
            .seedScheduledReminder(onVehicle: carA.vehicleID, dueInDays: 120)
        let carB = ReminderNotificationActionTestSupport.seedScheduledReminder(dueInDays: 120)

        await coordinator.reconcile(vehicleId: carA.vehicleID)
        await coordinator.reconcile(vehicleId: carB.vehicleID)

        let aIdentifiers = [carA.reminderID, carAextra].map { "reminder.\($0.uuidString).date" }
        let bIdentifier = "reminder.\(carB.reminderID.uuidString).date"
        let pending = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
        for identifier in aIdentifiers + [bIdentifier] {
            XCTAssertTrue(pending.contains(identifier),
                          "precondition: reconcile must arm \(identifier)")
        }

        // Archive car A and reconcile it - the RV.81 strip.
        ReminderNotificationActionTestSupport.archive(carA.vehicleID)
        await coordinator.reconcile(vehicleId: carA.vehicleID)

        let after = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
        for identifier in aIdentifiers {
            XCTAssertFalse(after.contains(identifier),
                           "archiving must cancel the archived car's pending request; still pending: "
                               + identifier)
        }
        XCTAssertTrue(after.contains(bIdentifier),
                      "archiving car A must not touch car B's armed requests - only the archived car's")
    }

    /// The reverse direction, which a one-way fix hides: unarchiving a car
    /// must RE-ARM its reminders. A car that comes back from the archive is
    /// not silently mute (mutation 2). Same real-center, real-coordinator path
    /// as the strip.
    func testUnarchivingReArmsThatCarsReminders() async throws {
        let coordinator = ReminderNotificationCoordinator()

        let car = ReminderNotificationActionTestSupport.seedScheduledReminder(dueInDays: 120)
        await coordinator.reconcile(vehicleId: car.vehicleID)
        let identifier = "reminder.\(car.reminderID.uuidString).date"
        let armed = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
        XCTAssertTrue(armed.contains(identifier),
                      "precondition: the live car must arm before archiving")

        // Archive: the request is cancelled.
        ReminderNotificationActionTestSupport.archive(car.vehicleID)
        await coordinator.reconcile(vehicleId: car.vehicleID)
        let stripped = await ReminderNotificationActionTestSupport.allPendingIdentifiers()
        XCTAssertFalse(stripped.contains(identifier),
                       "precondition: archiving must strip the car's armed request")

        // Unarchive: the same reconcile that stripped now re-arms.
        ReminderNotificationActionTestSupport.unarchive(car.vehicleID)
        await coordinator.reconcile(vehicleId: car.vehicleID)

        let rearmed = try await waitForPending(identifier: identifier, timeout: 5)
        XCTAssertEqual(rearmed, identifier,
                       "unarchiving must re-arm the car's reminders - a restored car is not mute")
    }

    // MARK: - RV.81 coordinator orchestration (recording seam)

    /// The real-center tests above cannot run on every host: the simulator's
    /// notification daemon has been observed dropping every `add` from a
    /// test-hosted process, so "the request is not pending" would be vacuous
    /// there. This suite drives the REAL coordinator - same repository, same
    /// plan, same archive/unarchive calls - against a recording scheduler, and
    /// asserts the IDENTIFIERS the reconcile asked the seam to cancel and the
    /// reminders it asked to arm. The seam is the only difference from the
    /// center-based tests; the orchestration under test is identical.
    func testCoordinatorArchiveStripCancelsOnlyTheArchivedCarsIdentifiers() async throws {
        let scheduler = RecordingNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduling: scheduler)

        let carA = ReminderNotificationActionTestSupport.seedScheduledReminder(dueInDays: 120)
        let carAextra = ReminderNotificationActionTestSupport
            .seedScheduledReminder(onVehicle: carA.vehicleID, dueInDays: 120)
        let carB = ReminderNotificationActionTestSupport.seedScheduledReminder(dueInDays: 120)

        await coordinator.reconcile(vehicleId: carA.vehicleID)
        await coordinator.reconcile(vehicleId: carB.vehicleID)

        let aDateIDs = [carA.reminderID, carAextra].map {
            "reminder.\($0.uuidString).date"
        }
        XCTAssertTrue(aDateIDs.allSatisfy { id in
            scheduler.scheduled.contains { $0.identifier == id }
        }, "precondition: reconciling the live car arms both its reminders")
        XCTAssertTrue(scheduler.scheduled.contains { $0.identifier == "reminder.\(carB.reminderID.uuidString).date" })

        // Archive car A and reconcile it: the strip asks the seam to cancel A's
        // identifiers (all three kinds, matching the identifier format), never
        // B's. The assertions are scoped to the cancels the ARCHIVE reconcile
        // added: an earlier live reconcile of B legitimately cancelled B's
        // `.odometer` identifier (B has no odometer due), so the accumulated
        // record would otherwise trip the "never B" assertion on a fixture, not
        // a bug.
        let cancelledBefore = scheduler.cancelledIdentifiers.count
        ReminderNotificationActionTestSupport.archive(carA.vehicleID)
        await coordinator.reconcile(vehicleId: carA.vehicleID)
        let stripCancels = scheduler.cancelledIdentifiers[cancelledBefore...]

        for reminderID in [carA.reminderID, carAextra] {
            for kind in ["date", "odometer", "overdue"] {
                XCTAssertTrue(stripCancels.contains("reminder.\(reminderID.uuidString).\(kind)"),
                              "the strip must cancel every kind the archived car's reminder owns")
            }
        }
        XCTAssertFalse(stripCancels.contains { $0.hasPrefix("reminder.\(carB.reminderID.uuidString).") },
                       "archiving car A must never cancel car B's identifiers - the other car stays armed")
        XCTAssertTrue(ReminderNotificationActionTestSupport.reminderIsStillScheduled(carA.reminderID),
                      "the strip must not advance the archived car's reminder lifecycle (no stored .attention)")
    }

    func testCoordinatorUnarchiveReArmsThroughTheSameReconcile() async throws {
        let scheduler = RecordingNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduling: scheduler)

        let car = ReminderNotificationActionTestSupport.seedScheduledReminder(dueInDays: 120)
        await coordinator.reconcile(vehicleId: car.vehicleID)
        let identifier = "reminder.\(car.reminderID.uuidString).date"
        let armedBefore = scheduler.scheduled.filter { $0.identifier == identifier }.count
        XCTAssertEqual(armedBefore, 1, "precondition: the live car arms its date notification")

        // Archive: the strip schedules nothing.
        ReminderNotificationActionTestSupport.archive(car.vehicleID)
        await coordinator.reconcile(vehicleId: car.vehicleID)
        XCTAssertEqual(scheduler.scheduled.filter { $0.identifier == identifier }.count,
                       armedBefore,
                       "an archived car's reconcile must schedule nothing - it is a strip")

        // Unarchive: the same reconcile arms again - the car is not mute.
        ReminderNotificationActionTestSupport.unarchive(car.vehicleID)
        await coordinator.reconcile(vehicleId: car.vehicleID)
        XCTAssertEqual(scheduler.scheduled.filter { $0.identifier == identifier }.count,
                       armedBefore + 1,
                       "unarchiving must re-arm the car's reminders through the same reconcile that stripped")
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
