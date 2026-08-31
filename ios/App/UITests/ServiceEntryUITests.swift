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

    /// Scroll an element clear of the pinned save bar's top, not merely to where
    /// XCUITest calls it hittable: `isHittable` is true UNDER the bar, and a tap
    /// there hits Save instead (the PJ.7e failure mode - a tap "on" a field once
    /// saved the entry). The drag is anchored on the sheet's own hittable scroll
    /// view, and scrolling dismisses the keyboard (`.scrollDismissesKeyboard`).
    private func scrollClearOfSaveBar(_ app: XCUIApplication, _ element: XCUIElement) {
        let bar = app.buttons["serviceEntrySaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if element.isHittable && element.frame.maxY < barTop - 8 { return }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { return }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
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

        let delete = app.buttons["serviceEntryItemDelete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "serviceEntryItemDelete never appeared")
        // The item row can sit under the pinned save bar (`isHittable` ignores
        // the overlay), so scroll it clear by geometry before tapping.
        scrollClearOfSaveBar(app, delete)
        delete.tap()
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

    // MARK: - PJ.11 F9a on every write

    /// F9a is checked on the service save too (docs/JOURNEYS.md F9a): a
    /// service odometer typed below the timeline flags amber with a Fix
    /// affordance, and the save STILL succeeds (hard rule 13 - an implausible
    /// value is a warning, never a refusal; the flag lands with the record).
    func testOdometerConflictWarnsAmberWithFixAndStillSaves() {
        let app = launch()  // -seedVehicleForUITests: a prior fill at 119 486 km
        let add = app.buttons["serviceEntryAddItemButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let title = app.textFields["serviceEntryItemTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Oil service")

        // Replace the pre-filled "119 486" with the F9a typo (119 486 -> 11 948).
        let odometer = app.textFields["serviceEntryOdometerField"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        odometer.tap()
        let digits = (odometer.value as? String) ?? "119486"
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: digits.count)
        odometer.typeText(deletes)
        odometer.typeText("11948")

        let warning = app.staticTexts["serviceEntryOdometerConflictWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the amber F9a warning must name the conflict on the odometer card")
        let fix = app.buttons["serviceEntryOdometerConflictFixButton"]
        XCTAssertTrue(fix.exists, "the Fix affordance is the next step (hard rule 7)")
        fix.tap()

        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.isEnabled,
                      "a flagged record is saveable - the app suggests, the user decides (hard rule 13)")
        save.tap()

        // The save succeeds: the sheet dismisses back to Home and the service
        // appears in the log, flagged - the badge proves the save STAMPED the
        // conflict (a save that wrote `.none` would render no badge at all).
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10),
                      "save still succeeds - the sheet dismisses to Home")
        XCTAssertTrue(app.staticTexts["Service"].waitForExistence(timeout: 5),
                      "the saved service renders in the log")
        XCTAssertTrue(app.buttons["conflictBadgeButton"].firstMatch.waitForExistence(timeout: 5),
                      "the saved service carries its amber conflict badge - the save stamped it")
    }
}
