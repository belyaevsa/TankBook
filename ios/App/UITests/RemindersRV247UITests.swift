import XCTest

/// RV.247 - "Type amount" from the merged all-cars reminder list must log the
/// entry to the REMINDER's car, never the selected one. The list shows every
/// active car's reminders; completing a non-selected car's reminder opened the
/// entry sheet, which resolved its vehicle from the current selection, so the
/// entry landed on whichever car the user happened to have selected. The
/// notification deep link was right only because it selected the reminder's car
/// first; the list path never did.
///
/// The gate is the merged list's own two-car seed: Volvo is the default
/// selection, the Skoda "Oil change" is the soonest attention row, so the first
/// complete affordance belongs to the NON-selected car. After typing an amount
/// and saving, the entry must be in the Skoda's log and NOT the Volvo's - the
/// "not the other's" half is the assertion that catches the wrong-car write.
/// EN and RU, because the flow runs through the localized completion sheet.
@MainActor
extension RemindersUITests {

    /// Drives the full typed-amount flow and asserts the entry's home car.
    /// The selected car stays Volvo throughout (the list path never switches
    /// it), so the Volvo's log is the negative control and the Skoda's is the
    /// positive one.
    private func assertTypedAmountLandsOnTheRemindersCar(language: [String]) {
        let app = XCUIApplication()
        // `-seedSettingsSignedIn`: the proof switches cars on Home through
        // `carSwitcherButton`, which only the signed-in Home renders - the
        // guest layout has no switcher (RV.251). Without the seed this test
        // passes only on a Keychain session a previous run left behind.
        app.launchArguments = ["-homeResetDatabase", "-seedRemindersAll", "-seedSettingsSignedIn",
                               "-presentScreen", "remindersAll"] + language
        app.launch()

        // The Skoda oil change (+3 d) sorts ahead of the Volvo insurance
        // (+12 d), so the first complete affordance is the non-selected car's.
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()

        let typeAmount = app.buttons["reminderCompleteTypeAmount"]
        XCTAssertTrue(typeAmount.waitForExistence(timeout: 5),
                      "the completion sheet must offer the typed door")
        typeAmount.tap()

        // The service entry opens pre-filled with the reminder's title; type the
        // amount the completion sheet exists to log.
        let cost = app.textFields["serviceEntryItemCost"].firstMatch
        XCTAssertTrue(cost.waitForExistence(timeout: 5))
        cost.tap()
        cost.typeText("89.00")

        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "a titled, priced line item is saveable")
        save.tap()

        // Back on the merged list; pop to the Log root. The selection is still
        // Volvo, so the entry must NOT be in its log. The list is anchored by
        // its merged-only create card, never the nav-bar title - the title is
        // localized and reads differently in RU.
        XCTAssertTrue(app.buttons["remindersAllNewReminderButton"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Oil change"].waitForExistence(timeout: 3),
                       "the entry must not be in the selected (Volvo) car's log")

        // Switch to the reminder's car: the entry IS there. This is the half
        // that proves the entry exists at all - the negative alone would pass
        // if the save had silently dropped it.
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        XCTAssertTrue(app.buttons["carSwitcherAddCar"].waitForExistence(timeout: 5),
                      "the garage sheet must open")
        let skoda = app.buttons.matching(identifier: "carSwitcherRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "Skoda Octavia")).firstMatch
        XCTAssertTrue(skoda.waitForExistence(timeout: 5))
        skoda.tap()
        XCTAssertTrue(app.staticTexts["Oil change"].waitForExistence(timeout: 10),
                      "the entry must be in the reminder's car's log")
    }

    func testTypedAmountFromTheMergedListLogsToTheRemindersCar() {
        assertTypedAmountLandsOnTheRemindersCar(language: [])
    }

    func testTypedAmountFromTheMergedListLogsToTheRemindersCarInRussian() {
        assertTypedAmountLandsOnTheRemindersCar(
            language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
    }
}
