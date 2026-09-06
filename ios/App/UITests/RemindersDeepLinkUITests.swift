import XCTest

/// RV.74 - a tapped reminder notification must land on the car it belongs to.
/// The defect: `RemindersView` scoped itself to the SELECTED car, and the deep
/// link never changed the selection, so a reminder on car B tapped while car A
/// was selected silently showed car A's list and took the "stale tap" branch
/// for a reminder that existed. The fix resolves the reminder id FIRST - the id
/// is the fact, the selected car is not - selects its live car (never an
/// archived one) and lands on the merged all-cars list, where a deep link
/// cannot be the wrong car.
///
/// Vacuous traps this suite is built against: asserting the Reminders screen
/// appeared (it already does today - it is the wrong car's); seeding ONE car
/// (the bug cannot exist there); asserting the deep-link route was set rather
/// than what the screen then shows.
@MainActor
final class RemindersDeepLinkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(replaying identifier: String,
                        seed: String = "-seedRemindersDeepLink") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", seed,
                               "-replayNotificationResponse", identifier]
        app.launch()
        return app
    }

    /// The live two-car case, end to end: car A (Volvo) is the default
    /// selection, the tapped reminder belongs to car B (Skoda). The completion
    /// flow for THAT reminder must surface (not the first row's), the landing
    /// must be the merged list (rows carry car chips), and the app must be on
    /// car B afterwards.
    func testTappedReminderOnCarBSelectsCarBAndSurfacesItsCompletion() {
        let carB = "5C1A2B3C-4D5E-4F60-8A7B-6C5D4E3F2A1B"
        let app = launch(replaying: "reminder.\(carB).date")

        // The deep link lands on Reminders...
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10))

        // ... and it is the MERGED list: the rows carry the per-row car chips a
        // car-scoped list never draws. (The old landing showed one car's list
        // with no chips - asserting the screen appeared alone proves nothing.)
        XCTAssertTrue(app.staticTexts["reminderCarChip"].firstMatch.waitForExistence(timeout: 5),
                      "the deep link must land on the merged all-cars list, whose rows name their car")

        // The surfaced sheet is the reminder the identifier named - the Skoda
        // oil change, due LATER than the Volvo insurance row that sorts first.
        // A bug that surfaced "whichever row is first" would show the insurance.
        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5),
                      "the tapped reminder's completion flow must surface")
        XCTAssertTrue(app.staticTexts["Oil change – done"].exists,
                      "the sheet is the reminder the tap named, not the first row")
        XCTAssertFalse(app.staticTexts["Insurance renewal – done"].exists,
                       "the sheet must be the Skoda reminder, never the Volvo one that sorts first")

        // Dismiss the sheet and go back to the Log root: the app is on car B.
        skip.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitForCar("Skoda Octavia", app: app)
    }

    /// The genuine stale case must keep working (hard rule 7): a deleted
    /// reminder lands on the plain merged list - never an error, never a
    /// detour - and the app does not switch to the deleted reminder's car.
    func testReplayedTapForDeletedReminderLandsOnThePlainList() {
        let deleted = "7A9B8C7D-6E5F-4A3B-8C2D-1E0F9A8B7C6D"
        let app = launch(replaying: "reminder.\(deleted).date")

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10),
                      "a stale tap must still land on Reminders - never an error, never a detour")

        // The plain list rendered (both live reminders, each naming its car),
        // and NO completion sheet surfaced for a reminder that no longer exists.
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Oil change"].exists)
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists)
        XCTAssertFalse(app.staticTexts["Brake check"].exists,
                       "the deleted reminder must not surface anywhere")
        XCTAssertFalse(app.buttons["reminderCompleteSkip"].waitForExistence(timeout: 3),
                       "a deleted reminder must not surface a completion flow")

        // No detour, no error surface: the app is still on car A (the default).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitForCar("Volvo V60", app: app)
    }

    /// The archived-car rule (decided, RV.74): never switch the selection to an
    /// archived car - the user still reaches their reminder (its completion
    /// flow surfaces over the merged list), and the app does not silently make
    /// a put-away car current again. Uses the `-seedRemindersDeepLinkArchived`
    /// seed, which is the deep-link state with car B archived after its
    /// reminder was armed.
    func testTappedReminderOnArchivedCarReachesItWithoutSwitchingSelection() {
        let carB = "5C1A2B3C-4D5E-4F60-8A7B-6C5D4E3F2A1B"
        let app = launch(replaying: "reminder.\(carB).date",
                         seed: "-seedRemindersDeepLinkArchived")

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10))

        // The merged list is the landing (active cars' rows carry chips)...
        XCTAssertTrue(app.staticTexts["reminderCarChip"].firstMatch.waitForExistence(timeout: 5))

        // ... and the archived reminder's completion flow still surfaces - the
        // user reaches their reminder even though its row is not drawn.
        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5),
                      "an armed reminder on an archived car must still be reachable")
        XCTAssertTrue(app.staticTexts["Oil change – done"].exists)

        // Dismiss, pop back: the selection was NOT switched to the archived car.
        skip.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitForCar("Volvo V60", app: app)
    }

    /// Waits until the Home header names the given car - the observable half of
    /// "the app is on car B". Polling because the switch lands while Reminders
    /// is pushed, and Home reloads behind it.
    private func waitForCar(_ name: String, app: XCUIApplication) {
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5),
                      "Home's car switcher never appeared")
        let predicate = NSPredicate(format: "label == %@", name)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: switcher)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "the app must be on \(name); the header read '\(switcher.label)'")
    }
}
