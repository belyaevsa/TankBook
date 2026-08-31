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
}
