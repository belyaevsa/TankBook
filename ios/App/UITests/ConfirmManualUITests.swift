import XCTest

/// P1.3 ConfirmManual sheet tests. The core rule: type any two of total /
/// litres / price, the third derives on save; the save bar is disabled until
/// two of the three exist (the artboard's "Enter total and liters to save"
/// state) and enables live the moment the second value is typed. All three
/// typed runs the cross-check: a mismatch shows amber, the check line refuses
/// to lock, and "save anyway" still works. The currency chip row is one tap.
@MainActor
final class ConfirmManualUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-seedVehicleForUITests"]
        app.launch()
        return app
    }

    private func openManualForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    // MARK: - Save gating

    func testSaveDisabledUntilTwoOfThreeShowsCaption() {
        let app = launch()
        openManualForm(app)

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // Nothing typed: save is disabled and the artboard's caption is up.
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].exists)

        // One value still does not unlock save.
        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("71.02")
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].exists)
    }

    func testSaveEnablesLiveAsSoonAsSecondValueIsTyped() {
        let app = launch()
        openManualForm(app)

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("71.02")
        XCTAssertFalse(save.isEnabled)

        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("42.30")

        // The second value flips save on live and drops the caption.
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.staticTexts["Enter total and liters to save"].exists)
    }

    // MARK: - Cross-check mismatch (F2)

    func testCrossCheckMismatchShowsAmberRefusesLockButSaveAnywayWorks() {
        let app = launch()
        openManualForm(app)

        // 10 L x 2.10 = 21.00 vs total 20.00: diff 1.00 > max(0.02, 0.10).
        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("20.00")
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("10")
        let price = app.textFields["manualFillUpPricePerLField"]
        price.tap()
        price.typeText("2.10")

        // The amber message renders with the documented copy...
        let mismatch = app.staticTexts["manualFillUpCrossCheckMismatch"]
        XCTAssertTrue(mismatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["these don't multiply up – check the amber field"].exists)
        // ...and the check line refuses to lock.
        XCTAssertFalse(app.staticTexts["manualFillUpCheckLineLocked"].exists)

        // "Save anyway" always exists: the save bar stays enabled and works.
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5))
    }

    // MARK: - Currency chips

    func testCurrencyChipRowIsReachableInOneTap() {
        let app = launch()
        openManualForm(app)

        let chip = app.buttons["manualFillUpCurrency_PLN"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.isHittable)

        // One tap selects the foreign currency; with no rates service the money
        // pair is rate-pending and the F9 hint replaces the neutral caption.
        chip.tap()
        XCTAssertTrue(app.staticTexts["manualFillUpConversionHint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["≈ – · converts when online"].exists)
    }
}
