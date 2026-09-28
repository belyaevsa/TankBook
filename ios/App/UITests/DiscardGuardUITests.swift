import XCTest

/// Exercises the reusable discard-guard mechanism (SCREENMAP navigation rule 1):
/// a sheet with unsaved typed input asks before discarding; a sheet with only
/// scanned data discards silently.
@MainActor
final class DiscardGuardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests"]
        app.launch()
        return app
    }

    func testTypedInputAsksBeforeDiscarding() {
        let app = launch()
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()

        let field = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("42")

        // Typed input -> close must ask, not dismiss.
        app.buttons["sheetCloseButton"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Discard"].exists)
        XCTAssertTrue(app.buttons["Keep editing"].exists)

        // Keep editing preserves the sheet and the input.
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        // Close again -> Discard -> sheet gone.
        app.buttons["sheetCloseButton"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        app.buttons["Discard"].tap()
        XCTAssertFalse(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts["Discard changes?"].exists)
    }

    // MARK: - Pushed forms: back navigation asks too

    /// Opens a form the way a user does: from its list, so back has a screen
    /// to return to.
    private func open(_ arguments: [String], newButton: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        let button = app.buttons[newButton]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(newButton) never appeared")
        button.tap()
        return app
    }

    /// A typed tyre-set name: back asks first, Keep editing keeps the name in
    /// the field, Discard leaves. With nothing typed, back is the plain one.
    func testATypedTyreSetNameAsksBeforeGoingBack() {
        let app = open(["-seedTireSets", "-presentScreen", "tireSets"], newButton: "tireSetsNewSetButton")
        let name = app.textFields["tireSetNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["formBackButton"].exists, "an untouched form keeps the system back")
        name.tap()
        name.typeText("Winter Nokian")

        app.buttons["formBackButton"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(name.value as? String, "Winter Nokian", "Keep editing keeps the typed name")

        app.buttons["formBackButton"].tap()
        app.buttons["Discard"].tap()
        XCTAssertFalse(name.waitForExistence(timeout: 3), "Discard leaves the form")
    }

    /// The reminder form hides the tab bar, so back is its only way out - and a
    /// typed title makes it ask.
    func testATypedReminderTitleAsksBeforeGoingBack() {
        let app = open(["-presentScreen", "reminders", "-seedReminders"], newButton: "remindersNewReminderButton")
        let title = app.textFields["reminderFormTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("Oil change")

        app.buttons["formBackButton"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(title.value as? String, "Oil change")

        app.buttons["formBackButton"].tap()
        app.buttons["Discard"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 3))
    }
}
