import XCTest

/// A pump photo nothing was read from says so and asks for the numbers.
extension ConfirmManualUITests {
    /// A pump photo nothing was read from says so and asks for the
    /// numbers by hand - no "read from the pump display" alpha claim.
    func testPumpPhotoNothingReadAdmitsItAndAsksForTheNumbers() {
        let app = launchWithPrefill("-seedPumpCaptureNothingRead")
        openForm(app)
        let caption = app.staticTexts["manualFillUpEmptyScanCaption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label,
                       "Couldn't read the pump display – type the numbers from it, the photo stays attached.")
        XCTAssertFalse(app.staticTexts["Read from the pump display – this is in alpha. Check every field before saving."].exists,
                       "nothing was read, so nothing may be framed as a reading")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "keyboard up on Total")
    }
}
