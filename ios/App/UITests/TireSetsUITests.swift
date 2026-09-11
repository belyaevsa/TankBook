import XCTest

/// P3.3 Tire sets tests (L4, docs/TESTING.md). The list renders each set with
/// its derived mileage and "–" where unknowable (never "0 km"); the form
/// creates and renames; and mounting from the ServiceEntry Tires mode both
/// requires a set and requires the odometer, then saves. Each test wipes the
/// database first (`-homeResetDatabase`) so the seed is deterministic.
@MainActor
final class TireSetsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    func testListRendersSetsWithMileageAndDash() {
        let app = launch(["-seedTireSets", "-presentScreen", "tireSets"])

        XCTAssertTrue(app.staticTexts["Winter Nokian"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Summer Michelin"].exists)

        // Two mileage lines: the mounted set's derived figure (grouped with the
        // shared U+00A0 separator) and the never-mounted set's honest "–".
        let mileages = app.staticTexts.matching(identifier: "tireSetMileage")
        XCTAssertEqual(mileages.count, 2, "each set shows exactly one mileage line")

        let first = mileages.element(boundBy: 0).label
        XCTAssertTrue(first.contains("18\u{00A0}400"), "winter mileage was \(first)")
        XCTAssertTrue(first.contains("km"), "winter mileage was \(first)")

        XCTAssertEqual(mileages.element(boundBy: 1).label, "–",
                       "a never-mounted set renders a dash, never a zero")

        // Zero is a claim and it is false: it must not appear anywhere.
        XCTAssertFalse(app.staticTexts["0 km"].exists, "zero must never stand in for unknown")
    }

    func testEmptyStateRenders() {
        let app = launch(["-presentScreen", "tireSets"])

        XCTAssertTrue(app.staticTexts["No tire sets yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["tireSetEmptyState"].exists)
        XCTAssertTrue(app.buttons["tireSetsNewSetButton"].exists)
    }

    func testFormCreatesARenamableSet() {
        let app = launch(["-seedTireSets", "-presentScreen", "tireSets"])

        // Create: the list is reachable from the New button, the name gates
        // save, and the new set appears in the list.
        let newButton = app.buttons["tireSetsNewSetButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.tap()

        let nameField = app.textFields["tireSetNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tireSetSaveButton"].isEnabled,
                       "a blank name must not save")

        nameField.tap()
        nameField.typeText("All-season Pirelli")
        XCTAssertTrue(app.buttons["tireSetSaveButton"].isEnabled)

        app.buttons["tireSetSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["All-season Pirelli"].waitForExistence(timeout: 10))

        // Rename: tapping the row reopens the form pre-filled with its name.
        app.staticTexts["All-season Pirelli"].tap()
        let renameField = app.textFields["tireSetNameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        XCTAssertEqual(renameField.value as? String, "All-season Pirelli")

        renameField.tap()
        renameField.typeText(" XL")
        app.buttons["tireSetSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["All-season Pirelli XL"].waitForExistence(timeout: 10))
    }

    func testMountingFromTiresModeRequiresASetAndTheOdometer() {
        let app = launch(["-seedTireSetsNoOdometer", "-presentScreen", "serviceEntry"])

        // Enter the Tires mode (the Service mode is the default).
        let tiresMode = app.buttons["serviceEntryModeTires"]
        XCTAssertTrue(tiresMode.waitForExistence(timeout: 10))
        tiresMode.tap()

        // No set chosen yet: Save is gated and names the next step.
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["serviceEntrySaveHint"].exists)

        // Mount a set. With no odometer anywhere on the car, the P3.1a rule
        // (a mounted set anchors the span) makes the odometer required: the
        // warning appears and Save stays gated.
        let picker = app.buttons["serviceEntryTireSetPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "serviceEntryTireSetPicker never appeared")
        picker.tap()
        let winter = app.buttons["Winter Nokian"]
        XCTAssertTrue(winter.waitForExistence(timeout: 5), "Winter Nokian never appeared")
        winter.tap()

        XCTAssertTrue(app.staticTexts["serviceEntryOdometerWarning"].waitForExistence(timeout: 5),
                      "mounting a set makes the odometer required")
        XCTAssertFalse(save.isEnabled)

        // Fill the odometer and the swap saves.
        let odometer = app.textFields["serviceEntryOdometerField"]
        odometer.tap()
        odometer.typeText("120000")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["serviceEntryModeTires"].waitForNonExistence(timeout: 10),
                      "saving the swap closes the sheet")
    }

    // MARK: - PJ.26 the purchase link

    /// A `.parts` expense offers "Make this a tire set"; tapping it writes the
    /// link, and the set form then shows the purchase it came from. The door is
    /// not the deliverable - the link is - so the assertion walks to the set and
    /// reads its purchase, not just the button.
    func testMakeTireSetFromPartsExpenseLinksTheSet() {
        let app = launch(["-seedEditEntryScannedExpense", "-presentScreen", "editEntry"])

        let make = app.buttons["makeTireSetButton"]
        XCTAssertTrue(make.waitForExistence(timeout: 10),
                      "the parts expense must offer the tire-set door")
        make.tap()

        let link = app.buttons["tireSetPurchaseLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "making the set must show the link on the expense")
        link.tap()

        XCTAssertTrue(app.textFields["tireSetNameField"].waitForExistence(timeout: 5),
                      "the link must open the set it names")
        XCTAssertTrue(app.staticTexts["Winter wiper blades"].waitForExistence(timeout: 5),
                      "the set form must show the purchase it came from")
    }

    // MARK: - PJ.27 the seasonal swap reminder

    /// Mounting a set proposes the next swap: a `.tires` reminder anchored at
    /// the mount, recurring by months. Accepting it puts it on the reminders
    /// list, which is the loop J7b promises.
    func testMountingASetOffersASwapReminder() {
        let app = launch(["-seedTireSetsNoOdometer", "-presentScreen", "serviceEntry"])

        app.buttons["serviceEntryModeTires"].tap()
        let picker = app.buttons["serviceEntryTireSetPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        let winter = app.buttons["Winter Nokian"]
        XCTAssertTrue(winter.waitForExistence(timeout: 5))
        winter.tap()

        let odometer = app.textFields["serviceEntryOdometerField"]
        odometer.tap()
        odometer.typeText("120000")
        app.buttons["serviceEntrySaveButton"].tap()

        XCTAssertTrue(app.staticTexts["serviceReminderOfferHeadline"].waitForExistence(timeout: 10),
                      "a mount must propose the next swap, never mount in silence")
        let months = app.textFields["serviceReminderOfferMonthsField"]
        XCTAssertTrue(months.exists, "the seasonal cadence is a months interval")
        XCTAssertEqual(months.value as? String, "6",
                       "the seasonal swap suggestion is six months")

        app.buttons["serviceReminderOfferCreateButton"].tap()

        app.terminate()
        app.launchArguments = ["-presentScreen", "remindersAll"]
        app.launch()
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Winter Nokian"].waitForExistence(timeout: 5),
                      "the accepted swap reminder must appear in the reminders list")
    }
}
