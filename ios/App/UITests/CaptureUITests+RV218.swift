import XCTest

/// RV.218: the F2 residue's "consumption outlier check on save". A fill whose
/// closing segment implies a figure outside the car's plausible band raises the
/// SAME amber warn surface the timeline flags use (`manualFillUpOdometerWarning`
/// is the F9a timeline row; `manualFillUpConsumptionWarning` is this one), names
/// its next step, and NEVER blocks the save (docs/SCHEMA.md, "Bands are wide and
/// soft on purpose"). The `-screenshotConsumptionOutlier` hook sets 8 L over the
/// 500 km since the seeded prior full fill = 1.6 L/100km, below the ICE floor -
/// the F2 misread-litre case.
///
/// Split into an extension (the `VehicleDetailUITests+RV182` precedent) so the
/// base `CaptureUITests` body stays under the SwiftLint file-length ceiling;
/// `-only-testing:.../CaptureUITests` still runs these methods.
extension CaptureUITests {

    private func launchOutlier(russian: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-screenshotConsumptionOutlier"]
        if russian {
            app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launch()
        return app
    }

    private func openOutlierForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10))
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5),
                      "Type it must present the manual form")
    }

    /// The warn renders with the engine's figure and both next steps, and Save
    /// is still enabled - the whole point is that it is a hint, not a gate.
    func testConsumptionOutlierWarnRendersAndNeverBlocksSave() {
        let app = launchOutlier(russian: false)
        openOutlierForm(app)

        let warning = app.staticTexts["manualFillUpConsumptionWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the consumption outlier warn must render on the Confirm sheet")
        XCTAssertTrue(warning.label.contains("1.6"),
                      "the warn must quote the engine's figure, was '\(warning.label)'")
        XCTAssertTrue(warning.label.localizedCaseInsensitiveContains("litres"),
                      "the warn must name the litres next step, was '\(warning.label)'")
        XCTAssertTrue(warning.label.localizedCaseInsensitiveContains("odometer"),
                      "the warn must name the odometer next step, was '\(warning.label)'")

        // Both next steps are present; litres rank first (the F2 case).
        let checkLiters = app.buttons["manualFillUpConsumptionCheckLitersButton"]
        let checkOdometer = app.buttons["manualFillUpConsumptionCheckOdometerButton"]
        XCTAssertTrue(checkLiters.waitForExistence(timeout: 5),
                      "the litres next step must render")
        XCTAssertTrue(checkOdometer.exists, "the odometer next step must render")
        XCTAssertEqual(checkLiters.label, "Check litres")
        XCTAssertEqual(checkOdometer.label, "Check odometer")

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isEnabled,
                      "a consumption outlier is a hint - Save must stay enabled")
    }

    /// The same warn in Russian, where the sentence and the two chips are the
    /// overflow check (hard rule 10).
    func testConsumptionOutlierWarnRendersInRussian() {
        let app = launchOutlier(russian: true)
        openOutlierForm(app)

        let warning = app.staticTexts["manualFillUpConsumptionWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the consumption outlier warn must render in Russian")
        XCTAssertTrue(warning.label.contains("1.6"),
                      "the RU warn must quote the engine's figure, was '\(warning.label)'")
        XCTAssertTrue(warning.label.localizedCaseInsensitiveContains("литры"),
                      "the RU warn must name the litres next step, was '\(warning.label)'")
        XCTAssertTrue(warning.label.localizedCaseInsensitiveContains("пробег"),
                      "the RU warn must name the odometer next step, was '\(warning.label)'")

        XCTAssertEqual(app.buttons["manualFillUpConsumptionCheckLitersButton"].label,
                       "Проверить литры")
        XCTAssertEqual(app.buttons["manualFillUpConsumptionCheckOdometerButton"].label,
                       "Проверить пробег")
        XCTAssertTrue(app.buttons["manualFillUpSaveButton"].isEnabled,
                      "the RU warn must not block the save either")
    }
}
