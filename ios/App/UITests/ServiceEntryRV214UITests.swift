import XCTest

/// RV.214 - the create gate accepts a service the Log can name without a titled
/// line item: a vendor-only record and the vendor-less untitled lump sum the
/// invoice splitter produces (J7's honest fallback), and the disabled-save hint
/// names what the new rule is still missing. EN and RU because the hint is the
/// one new user-facing string and Russian runs longer than English.
@MainActor
extension ServiceEntryUITests {

    private func launchRV214(_ seed: String, russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", seed, "-presentScreen", "serviceEntry"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// The vendor-less untitled lump sum is a normal record: Save is reachable
    /// and the saved row appears in the Log named from its category.
    func testAVendorlessUntitledLumpSumSavesAndTheLogNamesTheCategory() {
        let app = launchRV214("-seedServiceEntryUntitledLumpSum")
        let cost = app.textFields["serviceEntryItemCost"].firstMatch
        XCTAssertTrue(cost.waitForExistence(timeout: 10),
                      "the scanned lump sum's line must render")

        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isEnabled,
                      "a vendor-less untitled lump sum is a record - the Log names it (RV.187)")
        save.tap()

        let row = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "the saved lump sum must appear in the Log")
        XCTAssertTrue(row.label.contains("Other"),
                      "the Log row must be named from the category; was '\(row.label)'")
    }

    func testAVendorlessUntitledLumpSumSavesAndTheLogNamesTheCategoryInRussian() {
        let app = launchRV214("-seedServiceEntryUntitledLumpSum", russian: true)
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled,
                      "the vendor-less lump sum must save in RU too")
        save.tap()

        let row = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.label.contains("Прочее"),
                      "the RU Log row must be named from the category; was '\(row.label)'")
    }

    /// Hard rule 7: the disabled Save names the missing step under the new rule.
    func testTheDisabledSaveHintNamesWhatIsMissing() {
        let app = launchRV214("-seedVehicleForUITests")
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertFalse(save.isEnabled, "a blank service must not save")

        let hint = app.staticTexts["serviceEntrySaveHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertEqual(hint.label, "Add a vendor or a line item to save")
    }

    func testTheDisabledSaveHintNamesWhatIsMissingInRussian() {
        let app = launchRV214("-seedVehicleForUITests", russian: true)
        let hint = app.staticTexts["serviceEntrySaveHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertEqual(hint.label, "Добавьте поставщика или позицию, чтобы сохранить")
    }
}
