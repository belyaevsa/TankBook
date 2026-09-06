import XCTest

/// RV.71 (2026-09-05, product owner): a scanned receipt whose fuel kind the
/// car does not offer warns at scan moment on the Confirm sheet. The warning
/// never blocks the save and never rewrites either value (hard rule 13); the
/// × dismisses it for the sheet. The L1 rule table lives in core
/// (`FuelKindMismatchTests`); these tests pin the rendering, the non-blocking
/// save and the must-NOT-warn case (a rule that fires on everything is not a
/// rule). The helpers (`launchWithPrefill`, `openForm`, `fieldValue`) live on
/// `ConfirmManualUITests` in ConfirmManualUITests.swift; this extension runs
/// in the same class.
@MainActor
extension ConfirmManualUITests {

    private func mismatchWarning(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["manualFillUpFuelMismatchWarning"]
    }

    private func valueOf(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    func testMismatchedScanWarnsAndNeverBlocksTheSave() {
        // The default seeded car is petrol-95-only; the seed scan is diesel
        // (RV.71): the two disagree and the warn must render at scan moment.
        let app = launchWithPrefill("-seedConfirmPrefillFuelMismatch")
        openForm(app)

        let warning = mismatchWarning(app)
        XCTAssertTrue(warning.waitForExistence(timeout: 10),
                      "a diesel receipt on a petrol-95 car must warn at scan moment")

        // The warn names the scanned kind - the words carry the meaning
        // (hard rule 5: never colour alone).
        let message = app.staticTexts["manualFillUpFuelMismatchMessage"]
        XCTAssertTrue(message.exists)
        XCTAssertTrue(message.label.contains("Diesel"),
                      "the warn must name the scanned kind, got '\(message.label)'")

        // Save stays reachable and WORKS with the warn on screen - the warn
        // never blocks (hard rule 13). No dismissal needed.
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "the mismatch warn must never gate the save")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "Save must work with the mismatch warn on screen")
    }

    func testDismissingTheMismatchWarnChangesNeitherValue() {
        let app = launchWithPrefill("-seedConfirmPrefillFuelMismatch")
        openForm(app)

        let warning = mismatchWarning(app)
        XCTAssertTrue(warning.waitForExistence(timeout: 10))

        // The pre-filled numbers are on screen; dismissing must not touch them
        // or the fuel selection (hard rule 13: the warn never rewrites a value).
        XCTAssertEqual(valueOf(app, "manualFillUpTotalField"), "71.02")
        XCTAssertEqual(valueOf(app, "manualFillUpLitersField"), "42.30")

        let dismiss = app.buttons["manualFillUpFuelMismatchDismiss"]
        XCTAssertTrue(dismiss.exists, "the warn must be dismissable")
        dismiss.tap()

        XCTAssertFalse(warning.exists, "dismissing must remove the warn")
        XCTAssertEqual(valueOf(app, "manualFillUpTotalField"), "71.02",
                       "dismissing the warn must not change the total")
        XCTAssertEqual(valueOf(app, "manualFillUpLitersField"), "42.30",
                       "dismissing the warn must not change the liters")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "Save must stay reachable after dismissing the warn")
    }

    func testMatchingScanShowsNoMismatchWarn() {
        // The seeded petrol-95 scan against the petrol-95 car agrees: no warn.
        // This is the UI guard against a rule that fires on everything - the
        // grade case would otherwise annoy every user daily.
        let app = launchWithPrefill("-seedConfirmPrefill")
        openForm(app)

        let warning = mismatchWarning(app)
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        XCTAssertFalse(warning.exists,
                       "a receipt whose kind matches the car must not warn")
    }

    func testMismatchWarnShowsOnTheScreenshotLaunchPath() {
        // The RV.71 screenshots launch the sheet directly (`-presentScreen
        // confirmManual`) rather than tapping Type it - pin that exact
        // configuration so the screenshot and a test cannot disagree about
        // whether the warn is on screen.
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedConfirmPrefillFuelMismatch",
                               "-presentScreen", "confirmManual"]
        app.launch()

        let warning = mismatchWarning(app)
        XCTAssertTrue(warning.waitForExistence(timeout: 10),
                      "the screenshot launch path must show the mismatch warn")
        let message = app.staticTexts["manualFillUpFuelMismatchMessage"]
        XCTAssertTrue(message.exists)
        XCTAssertTrue(message.label.contains("Diesel"),
                      "the warn must name the scanned kind, got '\(message.label)'")
    }
}
