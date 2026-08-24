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
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
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

// MARK: - P2.3 the scanned path lands in the SAME sheet

/// P2.3: the scanned path shares one sheet with the typed path (hard rule 15).
/// These tests pin the two rules this screen must not break: an all-nil
/// extraction is the ordinary empty form - never an error, never a "scan
/// failed" banner - and a dimmed field is still a fully editable default input
/// (hard rule 13). Plus the QR-anchor total, the swapped-pair lock that must
/// not gate saving, and the reduced-motion lock.
extension ConfirmManualUITests {

    private func launchWithPrefill(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", seed]
        app.launch()
        return app
    }

    private func openForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    // MARK: 1. Rule 15: an all-nil extraction is the ordinary empty form

    func testAllNilExtractionRendersTheOrdinaryEmptyForm() {
        let app = launchWithPrefill("-seedConfirmPrefillEmpty")
        openForm(app)

        // No scan-failure surfaces: no cross-check mismatch, no "no car" hint -
        // an all-nil extraction renders as the ordinary manual form, never as
        // an error. (The seed's F9a odometer conflict may show its own amber
        // row, exactly as it would on a typed form with the same data - that
        // is a timeline warning, not a scan-failure one.)
        XCTAssertFalse(app.staticTexts["manualFillUpCrossCheckMismatch"].exists)
        XCTAssertFalse(app.staticTexts["manualFillUpNoVehicleHint"].exists)
        // The neutral, unlocked check line is up, exactly as on a manual form.
        XCTAssertTrue(app.staticTexts["manualFillUpCheckLine"].exists)

        // Save is off with nothing typed...
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].exists)

        // ...and the sheet is savable once the user types.
        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("71.02")
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("42.30")
        XCTAssertTrue(save.isEnabled)
    }

    // MARK: 2. A nil field renders blank, never 0

    func testNilFieldsRenderBlankNotZero() {
        let app = launchWithPrefill("-seedConfirmPrefillSparse")
        openForm(app)

        // The extraction resolved only liters; total and price are nil and must
        // render as honest blanks - a zero is a wrong fact, a blank is an
        // honest absence.
        XCTAssertTrue((app.textFields["manualFillUpTotalField"].value as? String)?.isEmpty ?? true)
        XCTAssertTrue((app.textFields["manualFillUpPricePerLField"].value as? String)?.isEmpty ?? true)
        XCTAssertNotEqual(fieldValue(app, "manualFillUpTotalField"), "0")
        XCTAssertNotEqual(fieldValue(app, "manualFillUpPricePerLField"), "0.00")
        // The resolved field shows its real value, not a zeroed stand-in.
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")
    }

    // MARK: 3. Dimmed is not disabled (hard rule 13)

    func testDimmedFieldIsStillEditableAndFullyEnabled() {
        let app = launchWithPrefill("-seedConfirmPrefill")
        openForm(app)

        // liters + price resolved, total deriving: the resolved fields are
        // unconfirmed and dimmed, but a dimmed field is a default input, never
        // read-only.
        let liters = app.textFields["manualFillUpLitersField"]
        XCTAssertTrue(liters.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")
        XCTAssertTrue(liters.isEnabled, "a dimmed field must never be disabled")

        // Focus it, type, and the value changes - dimming never blocks editing.
        liters.tap()
        liters.typeText("5")
        XCTAssertNotEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")
        XCTAssertTrue(liters.isEnabled)

        // The dimmed price field is equally editable, and no trait marks any
        // figure field read-only.
        let price = app.textFields["manualFillUpPricePerLField"]
        XCTAssertTrue(price.isEnabled)
        price.tap()
        price.typeText("0")
        XCTAssertNotEqual(fieldValue(app, "manualFillUpPricePerLField"), "1.679")
    }

    // MARK: 4. The cross-check lock never gates saving (swapped-pair trap)

    func testSwappedPairStillLocksAndSaveIsNeverGated() {
        let app = launchWithPrefill("-seedConfirmPrefillSwapped")
        openForm(app)

        // 1.679 x 42.30 == 42.30 x 1.679: the parser swapped them and the
        // cross-check still reports verified. The lock proves consistency,
        // never assignment - so it must not gate saving.
        XCTAssertTrue(app.staticTexts["manualFillUpCheckLineLocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["manualFillUpCrossCheckMismatch"].exists)

        // The lock is decoration over the save gate: two of three typed is
        // enough to save, verified or not.
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
    }

    // MARK: 5. The QR anchor wins on the total

    func testQRDisagreesFillsTheQrTotal() {
        let app = launchWithPrefill("-seedConfirmPrefillQR")
        openForm(app)

        // OCR grabbed the VAT line (867.00); the QR grand total is exact and
        // outranks it, filling the field.
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "4334.83")
    }

    func testMixedReceiptKeepsTheFuelLine() {
        let app = launchWithPrefill("-seedConfirmPrefillMixed")
        openForm(app)

        // Grand total 50.00, fuel line 20.00 L x 2.00 = 40.00: the fill-up
        // amount is the fuel line (hard rule 4), never the grand total.
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "40.00")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "20.00")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "2.000")
    }

    // MARK: 6. Tap-to-verify crops

    func testTapToVerifyShowsTheCropOfTheSource() {
        let app = launchWithPrefill("-seedConfirmPrefill")
        openForm(app)

        // The liters row resolved from the scan carries the verify affordance.
        let verify = app.buttons["manualFillUpVerifyButton_volume"]
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        XCTAssertTrue(verify.isHittable)
        verify.tap()

        // The crop sheet opens with the source image reference.
        XCTAssertTrue(app.staticTexts["verifyCropCaption"].waitForExistence(timeout: 5))
        let done = app.buttons["verifyCropDoneButton"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertFalse(app.staticTexts["verifyCropCaption"].exists)
    }

    // MARK: 7. Reduced motion

    func testReducedMotionLockStillLandsWithoutAnimation() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-forceReduceMotion"]
        app.launch()
        openForm(app)

        // Drive a real unlocked -> locked transition with Reduce Motion forced
        // on: the reduced variant is the state change WITHOUT the spring, never
        // a missing state (the animation decision itself is unit-tested in
        // core, `ConfirmLockAnimation.shouldAnimate`).
        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("20.00")
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("10")
        let price = app.textFields["manualFillUpPricePerLField"]
        price.tap()
        price.typeText("2.00")

        XCTAssertTrue(app.staticTexts["manualFillUpCheckLineLocked"].waitForExistence(timeout: 5))
    }

    // MARK: 8. P2.4 the "Also on this receipt" section

    func testMixedReceiptShowsTheAlsoOnThisReceiptSection() {
        let app = launchWithPrefill("-seedConfirmPrefillMixedReceipt")
        openForm(app)

        // The section appears with its two lines and the footer.
        XCTAssertTrue(app.otherElements["mixedReceiptSection"].waitForExistence(timeout: 5))
        let wash = app.switches["mixedReceiptToggle_0"]
        let coffee = app.switches["mixedReceiptToggle_1"]
        XCTAssertTrue(wash.exists)
        XCTAssertTrue(coffee.exists)
        XCTAssertTrue(app.staticTexts["mixedReceiptFooter"].exists)

        // The car wash (car-related) defaults to accepted: the save bar counts
        // it, and the coffee (non-car) does not.
        XCTAssertTrue(app.buttons["manualFillUpSaveButton"].label.contains("1 expense"))

        // Flipping the coffee on updates the count live.
        coffee.tap()
        XCTAssertTrue(app.buttons["manualFillUpSaveButton"].label.contains("2 expenses"))
    }

    func testPlainReceiptRendersTheOrdinarySheetWithoutTheSection() {
        let app = launchWithPrefill("-seedConfirmPrefill")
        openForm(app)

        // No "Also on this receipt" section on an ordinary fill - the sheet is
        // the normal Confirm form (hard rule 15's sibling principle).
        XCTAssertFalse(app.otherElements["mixedReceiptSection"].exists)
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].exists)
    }
}
