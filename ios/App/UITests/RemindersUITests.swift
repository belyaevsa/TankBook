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

    func testCompleteOpensTheSheetAndSkipRecurs() {
        let app = launch(["-seedReminders"])

        // Every row carries a complete affordance; the attention row sorts
        // first, so the first match is the seeded "Insurance renewal".
        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        // The completion sheet opens (not a direct `.done` - P3.5).
        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderCompleteTypeAmount"].exists)

        skip.tap()

        // Skipping (`.done(nil)`) moves the row out of the attention group:
        // the chip is gone. The seeded reminder recurs every 12 months, so the
        // NEXT occurrence appears in Scheduled, anchored at the completion date
        // (docs/SCHEMA.md lifecycle: old rows become history, the next row is
        // new).
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["reminderChip"].exists,
                       "the completed attention row must leave the group")
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists,
                      "the recurring reminder's next occurrence is already scheduled")
    }

    func testSkipMovesANonRecurringRowIntoHistory() {
        let app = launch(["-seedReminders"])

        // Scheduled order is Winter tires (45 d), Inspection (~7 mo), Oil
        // change (~18 mo) - so the second complete button is the non-recurring
        // Winter tires row.
        let complete = app.buttons.matching(identifier: "reminderCompleteButton").element(boundBy: 1)
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        // A non-recurring reminder has no next occurrence: the row is gone,
        // now history ("oil changed 3× on time" - docs/SCHEMA.md).
        XCTAssertFalse(app.staticTexts["Winter tires"].waitForExistence(timeout: 3),
                       "a non-recurring reminder leaves the list when completed")
    }

    func testTypeAmountLandsInTheEntryWithThePrefill() {
        let app = launch(["-seedReminderComplete"])

        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        let typeAmount = app.buttons["reminderCompleteTypeAmount"]
        XCTAssertTrue(typeAmount.waitForExistence(timeout: 5))
        typeAmount.tap()

        // The ServiceEntry sheet opens carrying the reminder's pre-fill:
        // title, category and the current odometer.
        let itemTitle = app.textFields["serviceEntryItemTitle"].firstMatch
        XCTAssertTrue(itemTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(itemTitle.value as? String, "Oil change",
                       "the reminder title arrives as the item title")

        let odometer = app.textFields["serviceEntryOdometerField"]
        XCTAssertTrue(odometer.exists)
        XCTAssertTrue((odometer.value as? String)?.contains("119") == true,
                      "the current odometer arrives pre-filled; was \(String(describing: odometer.value))")

        // The pre-fill is editable (hard rule 13): every field is a default
        // input, never read-only.
        XCTAssertTrue(itemTitle.isEnabled, "the pre-filled title must stay editable")
        XCTAssertTrue(odometer.isEnabled, "the pre-filled odometer must stay editable")
    }
}
