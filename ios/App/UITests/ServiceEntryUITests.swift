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

    private func launch(_ seed: String = "-seedVehicleForUITests") -> XCUIApplication {
        let app = XCUIApplication()
        // The reset travels with every seed: seeds are idempotent and silently
        // do nothing on a populated database, which renders a different screen
        // while the capture or assertion still looks plausible.
        app.launchArguments = ["-homeResetDatabase", seed, "-presentScreen", "serviceEntry"]
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

    // MARK: - P3.1b, the scanned half

    /// The page strip renders only for a scanned record, and the ordinary typed
    /// sheet stays exactly the sheet P3.1a shipped (hard rule 15: one screen,
    /// two doors - the scan adds to it, it does not replace it).
    func testThePageStripRendersOnlyForAScannedRecord() {
        // The identifier sits on a horizontal ScrollView, so it surfaces as
        // `.scrollView` - `otherElements` does not match it. The negative case
        // below queries EVERY type on purpose: a strip leaking onto the typed
        // sheet would be a bug whatever view it happened to be built from.
        let scanned = launch("-seedServiceEntryScan")
        XCTAssertTrue(scanned.scrollViews["serviceEntryPageStrip"].waitForExistence(timeout: 10))
        XCTAssertTrue(scanned.staticTexts["serviceEntryPageCounter"].exists)
        XCTAssertTrue(scanned.buttons["serviceEntryAddPageButton"].exists)
        scanned.terminate()

        let typed = launch("-seedServiceEntry")
        XCTAssertTrue(typed.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10))
        XCTAssertFalse(typed.descendants(matching: .any)["serviceEntryPageStrip"].exists,
                       "a typed record must not grow a page strip")
    }

    /// Hard rule 13: a scanned value is a default input, not a fact. Every
    /// scanned row must still be editable - the dimming is presentation, never
    /// a lock. This is the assertion that catches a read-only pre-fill, which
    /// looks correct in a screenshot and is a bug.
    func testScannedLineItemsStayEditable() {
        let app = launch("-seedServiceEntryScan")
        let title = app.textFields["serviceEntryItemTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isEnabled, "a scanned title must remain editable")

        let cost = app.textFields["serviceEntryItemCost"].firstMatch
        XCTAssertTrue(cost.exists)
        XCTAssertTrue(cost.isEnabled, "a scanned cost must remain editable")

        let odometer = app.textFields["serviceEntryOdometerField"]
        XCTAssertTrue(odometer.exists)
        XCTAssertTrue(odometer.isEnabled, "the odometer stays editable after a scan")
    }

    /// J7: a failed split is the lump sum, and the lump sum is a normal record -
    /// "never force itemization". So the honest failure state carries no error
    /// text, no warning badge, and a save button that works.
    func testAFailedSplitShowsNoErrorAndStillSaves() {
        let app = launch("-seedServiceEntryScanLumpSum")
        XCTAssertTrue(app.textFields["serviceEntryItemTitle"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollViews["serviceEntryPageStrip"].exists,
                      "the bill stays attached to the lump sum")
        XCTAssertFalse(app.staticTexts["serviceEntryOdometerWarning"].exists)

        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isEnabled, "a lump sum with the bill attached is a perfectly good record")
    }
}
