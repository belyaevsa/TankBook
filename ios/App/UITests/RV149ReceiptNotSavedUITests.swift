import XCTest

/// RV.149 L4 - a fill-up's receipt photo can fail to save and the user is never
/// told (the expense path's PJ.28 report never reached the fill-up save). A
/// photo-write failure must still save the entry WITHOUT the photo (hard rule
/// 1) and must tell the user with the shared message - the same sentence the
/// expense save uses (docs/ERRORS.md -> Confirm, RV.149) - never a silent drop
/// (hard rule 8) and never a blocked save.
///
/// The failure is forced by `-seedConfirmReceiptWriteFails`: the scanned
/// prefill's source image is empty, so `jpegData` returns nil and the save's
/// photo write throws exactly as a storage failure would. The toast appears
/// after the sheet dismisses, over Home, for its auto-dismiss window.
@MainActor
final class RV149ReceiptNotSavedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchScannedFillUpThatCannotKeepItsPhoto(languageArgs: [String] = [])
        -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedConfirmPrefill", "-seedConfirmReceiptWriteFails"]
            + languageArgs
        app.launch()
        // The scanned path lands in the same Confirm sheet as the typed door
        // (hard rule 15); the prefill resolves liters + price, the total
        // derives, so Save is enabled without typing.
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        return app
    }

    /// The whole defect in one assertion pair: the entry still saves (never a
    /// blocked save) AND the user is told. Asserting only the first half is
    /// today's behaviour and the vacuous trap this row names.
    func testLostReceiptPhotoStillSavesTheFillUpAndTellsTheUser() {
        let app = launchScannedFillUpThatCannotKeepItsPhoto()

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled,
                      "a failing photo write must never gate the save (hard rule 1)")
        save.tap()

        // The entry lands: back on Home.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "the fill-up must save even though its receipt photo could not")

        // The user is told - with the SHARED message, the same sentence the
        // expense path shows (the localization gate and the RV.149 L1 guard
        // keep it one key; here the rendered words are the assertion).
        let message = "No space to keep the receipt photo – the entry was saved without it. "
            + "Free up space and re-scan it."
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5),
                      "a lost receipt photo must be reported, never silent (hard rule 8)")
    }

    /// The same moment in Russian - RU is where the sentence runs longest and
    /// where a truncated next step would break hard rule 7.
    func testLostReceiptPhotoTellsTheUserInRussian() {
        let app = launchScannedFillUpThatCannotKeepItsPhoto(
            languageArgs: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        let message = "Не хватило места для фото чека – запись сохранена без него. "
            + "Освободите место и отсканируйте чек снова."
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5),
                      "the Russian report must render in full, never truncated")
    }

    /// The report's other half: it is not noise. A save whose receipt photo
    /// DID land shows no lost-photo toast - this is the test that fails if the
    /// `lostPhoto` gate (the flag that drives the report) is ever deleted and
    /// the save starts reporting unconditionally.
    func testSuccessfulReceiptPhotoSaveShowsNoLostPhotoToast() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedConfirmPrefill"]
        app.launch()
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "the fill-up must save with its receipt photo")

        let message = "No space to keep the receipt photo – the entry was saved without it. "
            + "Free up space and re-scan it."
        XCTAssertFalse(app.staticTexts[message].waitForExistence(timeout: 2),
                       "a successful receipt save must not raise the lost-photo toast")
    }
}
