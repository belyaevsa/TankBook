import XCTest

/// P3.4 Reminders screen tests (L4, docs/TESTING.md). The list renders both
/// groups from the seed; the empty state reads as calm, not broken; and the
/// form saves and returns to the list with the new reminder visible. Each test
/// wipes the database first (`-homeResetDatabase`) so the seed is deterministic
/// regardless of test order - a seed is idempotent and silently no-ops on a
/// populated database.
@MainActor
final class RemindersUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", "reminders"] + arguments
        app.launch()
        return app
    }

    func testListRendersBothGroupsFromSeed() {
        let app = launch(["-seedReminders"])

        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].exists)

        // The attention row carries the artboard's literal "12 days" chip -
        // asserted against the literal, never recomputed (the seed fixes the
        // due date at now + 12 days).
        let chip = app.staticTexts["reminderChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "12 days", "chip was \(chip.label)")

        XCTAssertTrue(app.buttons["reminderCompleteButton"].exists)
        XCTAssertTrue(app.buttons["remindersNewReminderButton"].exists)
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists)
        XCTAssertTrue(app.staticTexts["Oil change"].exists)
        XCTAssertTrue(app.staticTexts["Winter tires"].exists)
    }

    func testEmptyStateRenders() {
        let app = launch([])

        XCTAssertTrue(app.staticTexts["No reminders yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reminderEmptyState"].exists)
        // The empty state is a calm starting point, not a dead end: the "New
        // reminder" action is still there.
        XCTAssertTrue(app.buttons["remindersNewReminderButton"].exists)
        XCTAssertFalse(app.staticTexts["remindersAttentionHeader"].exists)
        XCTAssertFalse(app.staticTexts["remindersScheduledHeader"].exists)
    }

    func testFormSavesAndReturnsToTheList() {
        let app = launch(["-seedReminders"])

        let newButton = app.buttons["remindersNewReminderButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.tap()

        let title = app.textFields["reminderFormTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Brake check")

        app.buttons["reminderFormAddDateButton"].tap()

        let save = app.buttons["reminderFormSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Returns to the list with the new reminder visible.
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Brake check"].waitForExistence(timeout: 5))
    }

    func testCompleteTakesTheRowToDone() {
        let app = launch(["-seedReminders"])

        // Every row carries a complete affordance; the attention row sorts
        // first, so the first match is the seeded "Insurance renewal".
        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        // Completing (as `.done(nil)`, the no-sheet path) moves the row out of
        // the attention group: the chip is gone. The seeded reminder recurs
        // every 12 months, so the NEXT occurrence appears in Scheduled,
        // anchored at the completion date - the "auto-rescheduled" loop
        // (docs/SCHEMA.md lifecycle: old rows become history, the next row is
        // new).
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["reminderChip"].exists,
                       "the completed attention row must leave the group")
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists,
                      "the recurring reminder's next occurrence is already scheduled")
    }
}
