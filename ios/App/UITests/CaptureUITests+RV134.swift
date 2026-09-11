import XCTest

/// RV.134: an imperial (miles/gallons) car's manual numbers card must name the
/// vehicle's own volume unit in the price label and the derive caption. The old
/// copy hardcoded the litre wording - "Price / L" and "fills in from total ÷
/// liters" - beside a volume field already labelled "gal", so one screen
/// contradicted itself. RU is the real check: the litre key renders "Цена / л",
/// the gallon key "Цена / гал".
///
/// Split into an extension (the `CaptureUITests+RV218` precedent) so the base
/// `CaptureUITests` body stays under the SwiftLint file-length ceiling;
/// `-only-testing:.../CaptureUITests` still runs this method.
extension CaptureUITests {

    /// The denied camera state is the typed door hard rule 15 requires, and it
    /// renders this same numbers card. `-seedVehicleMiles` is a modifier on
    /// `-seedVehicleForUITests`, which must be present for it to take effect.
    private func launchImperialManualForm(russian: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedVehicleMiles",
                               "-presentScreen", "capture", "-cameraStatus", "denied"]
        if russian {
            app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
        return app
    }

    func testImperialManualFormNamesGallonsInRussian() {
        let app = launchImperialManualForm(russian: true)
        XCTAssertTrue(app.staticTexts["Цена / гал"].waitForExistence(timeout: 10),
                      "an imperial car's price label must read gallons")
        XCTAssertFalse(app.staticTexts["Цена / л"].exists,
                       "an imperial car must never be shown the litre label")
        XCTAssertTrue(app.staticTexts["считается из суммы ÷ галлонов"].waitForExistence(timeout: 5),
                      "the derive caption must name gallons, not litres")
    }

    /// EN counterpart: the same selection, so the fix is not RU-only.
    func testImperialManualFormNamesGallonsInEnglish() {
        let app = launchImperialManualForm(russian: false)
        XCTAssertTrue(app.staticTexts["Price / gal"].waitForExistence(timeout: 10),
                      "an imperial car's price label must read gallons")
        XCTAssertFalse(app.staticTexts["Price / L"].exists,
                       "an imperial car must never be shown the litre label")
        XCTAssertTrue(app.staticTexts["fills in from total ÷ gallons"].waitForExistence(timeout: 5),
                      "the derive caption must name gallons, not litres")
    }
}
