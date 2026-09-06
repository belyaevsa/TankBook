import XCTest

/// RV.76 - the Home "Reminders · N due" row (design/screens/
/// RemindersEntry.dc.html, docs/SCREENMAP.md -> "Reminders across cars"). The
/// bug this closes: the Home banner was the only one-tap path and it rendered
/// only while something was already due, so a driver with nothing due had no
/// path at all and one with two due never saw the second. The row is the calm
/// door - ALWAYS present, whatever the count - and its count is the point: it
/// spans every live car and is derived at read time (hard rule 2), never
/// stored.
///
/// The vacuous trap this suite exists to avoid is asserting the row exists only
/// in the due case - the nothing-due window is the whole bug, so every test
/// here drives a seed and asserts what is and is not rendered.
@MainActor
final class RemindersEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Signed in (the row lives in the signed-in Home layout), English by
    /// default, database reset so each seed is deterministic.
    private func launch(args: [String],
                        language: [String] = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + language + args
        app.launch()
        return app
    }

    // MARK: - The calm window (nothing due)

    /// With reminders EXISTING but nothing due - the exact window that used to
    /// have no path at all - the entry point is present (no amber chip, no
    /// banner) and reaches the merged list, which shows the scheduled rows.
    func testNothingDueRowIsPresentAndReachesTheMergedList() {
        let app = launch(args: ["-seedHomeRemindersNothingDue"])

        let row = app.buttons["homeRemindersRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "with nothing due the Reminders door must still be present")
        XCTAssertFalse(app.staticTexts["homeRemindersDueCount"].exists,
                       "nothing due means no amber count chip")
        XCTAssertFalse(app.buttons["homeReminderViewButton"].exists,
                       "nothing due means the urgent banner is absent - the row is the only door")

        row.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5),
                      "the calm row must reach the merged list")
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 5),
                      "the merged list holds the scheduled reminders")
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists)
        XCTAssertTrue(app.staticTexts["Oil change"].exists)
    }

    // MARK: - The count spans every car

    /// With two reminders due on DIFFERENT cars the row's count reads 2 - the
    /// "when two things are due the second is invisible" window - and the
    /// banner still shows the single most urgent reminder (this replaces
    /// nothing). The count is derived: the seed writes reminders, never a
    /// number, so a hard-coded count cannot satisfy this test.
    func testTwoDueOnDifferentCarsCountReadsTwoAndBannerStays() {
        let app = launch(args: ["-seedHomeRemindersDue"])

        let chip = app.staticTexts["homeRemindersDueCount"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "two cars each with a due reminder must render the count chip")
        XCTAssertEqual(chip.label, "2 due",
                       "the count must span BOTH cars; chip was \(chip.label)")

        let view = app.buttons["homeReminderViewButton"]
        XCTAssertTrue(view.exists, "the urgent banner stays beside the calm row")
        XCTAssertTrue(textContaining(app, "Insurance renewal").exists,
                      "the banner still shows the most urgent reminder")
    }

    // MARK: - The empty state is the discovery path

    /// With NO reminders at all the row still exists; tapping it opens the
    /// merged list's empty state, whose ONE action is the FILLED "New
    /// reminder" - never the dashed card, which is the "add one more" idiom for
    /// a list that has rows. The filled action opens the create form asking
    /// which car (hard rule 13: nothing is silently picked for the user).
    func testEmptyStateFilledActionOpensTheForm() {
        let app = launch(args: ["-seedHomeEmptyVehicle"])

        let row = app.buttons["homeRemindersRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the row is present even with no reminders at all")
        row.tap()

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
        let filled = app.buttons["remindersEmptyNewReminderButton"]
        XCTAssertTrue(filled.waitForExistence(timeout: 5),
                      "the empty state must render its FILLED create action")
        XCTAssertFalse(app.buttons["remindersAllNewReminderButton"].exists,
                       "the dashed card is NOT the empty state's action")

        filled.tap()

        // The merged list's create asks which car: Save is inert and the hint
        // says the choice is required (the per-car door would pre-fill it).
        let save = app.buttons["reminderFormSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled,
                       "from the merged list the car is an explicit choice, never a silent pick")
        XCTAssertTrue(app.staticTexts["reminderFormCarRequiredHint"].exists)
    }

    // MARK: - Helpers

    private func textContaining(_ app: XCUIApplication, _ substring: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }
}
