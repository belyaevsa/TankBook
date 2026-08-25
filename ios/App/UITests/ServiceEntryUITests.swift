import XCTest

/// P3.1a ServiceEntry sheet tests. The screen renders its sections; a line item
/// can be added and its cost drives the header total live, and deleting it
/// reverts the total; and the discard guard still fires on a dirty form (the
/// reusable DiscardAwareSheet, exercised here through the same `hasUnsavedChanges`
/// binding contract the placeholder kept).
@MainActor
final class ServiceEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-presentScreen", "serviceEntry"]
        app.launch()
        return app
    }

    func testScreenRendersItsSections() {
        let app = launch()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["serviceEntryHeaderTotal"].exists)
        XCTAssertTrue(app.buttons["serviceEntryDateButton"].exists)
        XCTAssertTrue(app.textFields["serviceEntryOdometerField"].exists)
        XCTAssertTrue(app.buttons["serviceEntryAddItemButton"].exists)
        XCTAssertTrue(app.buttons["serviceEntrySaveButton"].exists)
    }

    func testAddingAndDeletingALineItemUpdatesTheTotal() {
        let app = launch()
        let add = app.buttons["serviceEntryAddItemButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let cost = app.textFields["serviceEntryItemCost"]
        XCTAssertTrue(cost.waitForExistence(timeout: 5))
        cost.tap()
        cost.typeText("89.00")

        let total = app.staticTexts["serviceEntryHeaderTotal"]
        XCTAssertTrue(total.label.contains("89.00"), "header total was \(total.label)")

        app.buttons["serviceEntryItemDelete"].tap()
        XCTAssertTrue(total.label.contains("0.00"), "header total was \(total.label)")
    }

    func testDiscardGuardFiresOnADirtyForm() {
        let app = launch()
        let vendor = app.textFields["serviceEntryVendorField"]
        XCTAssertTrue(vendor.waitForExistence(timeout: 10))
        vendor.tap()
        vendor.typeText("Bosch")

        app.buttons["sheetCloseButton"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Keep editing"].exists)
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 5))
    }
}
