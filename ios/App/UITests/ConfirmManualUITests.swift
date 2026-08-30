import XCTest

/// P1.3 ConfirmManual sheet tests. The core rule: type any two of total /
/// litres / price, the third derives on save; the save bar enables live the
/// moment the second value is typed; typing all three runs the cross-check
/// (mismatch shows amber, refuses to lock, "save anyway" still works).
@MainActor
final class ConfirmManualUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func launch(args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-seedVehicleForUITests"]
        app.launch()
        return app
    }

    /// Bring a field on screen and tap it. The stop condition is GEOMETRIC, not
    /// `isHittable`: `isHittable` is true under the pinned Save bar (the
    /// accessibility tree does not model the `safeAreaInset` overlay), and a tap
    /// there lands on Save - dismissing the sheet and reading as "the field
    /// vanished". The drag is anchored above the keyboard on the sheet's own
    /// hittable scroll view, never Home's behind it.
    @discardableResult
    private func focusField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if field.isHittable && field.frame.maxY < barTop - 8 { break }
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
        return field
    }

    /// Scroll an element clear of the pinned save bar's top, not merely to where
    /// XCUITest calls it hittable: `isHittable` is true UNDER the bar, and a tap
    /// there once saved the entry - the failure read as a missing button.
    func scrollClearOfSaveBar(_ app: XCUIApplication, _ element: XCUIElement) {
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if element.isHittable && element.frame.maxY < barTop - 8 { return }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { return }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
    }

    func openManualForm(_ app: XCUIApplication) {
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
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].exists)
    }

    func testSaveEnablesLiveAsSoonAsSecondValueIsTyped() {
        let app = launch()
        openManualForm(app)

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        XCTAssertFalse(save.isEnabled)

        let liters = focusField(app, "manualFillUpLitersField")
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
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("20.00")
        let liters = focusField(app, "manualFillUpLitersField")
        liters.typeText("10")
        let price = focusField(app, "manualFillUpPricePerLField")
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

    /// The chip row folds away while the entry is in the home currency (paying
    /// abroad is rare). This test once asserted "reachable in one tap"; it is
    /// now **one tap to reveal, one to choose**, and the guarantee that matters
    /// is `testCurrencyOpensItselfWhenItIsNotSimplyTheHomeCurrency`.
    func testCurrencyChipRowIsOneTapAway() {
        let app = launch()
        openManualForm(app)

        // Folded by default: the collapsed row names the currency in force.
        let collapsed = app.buttons["manualFillUpCurrencyCollapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manualFillUpCurrency_PLN"].exists,
                       "the chip row must be folded while the entry is in the home currency")

        collapsed.tap()

        // Folded, the section sits BELOW the numbers card, so the chips can be
        // off-screen on a short device even once expanded - `exists` is not
        // `isHittable`. Scroll to them the way a user would.
        let chip = app.buttons["manualFillUpCurrency_PLN"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        var scrolls = 0
        while !chip.isHittable && scrolls < 5 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(chip.isHittable, "the chip row must be reachable after expanding")

        // Selecting the foreign currency: with no rates service the money pair
        // is rate-pending and the conversion card appears (the F9 state).
        chip.tap()
        XCTAssertTrue(app.otherElements["manualFillUpConversionCard"].waitForExistence(timeout: 5))
    }

    /// The fold is never allowed to hide a decision the user must make: a
    /// low-confidence currency has to ASK rather than convert (P2.5), and a
    /// genuinely foreign entry has a conversion the user must see. Both open the
    /// section by themselves, with no tap at all.
    func testCurrencyOpensItselfWhenItIsNotSimplyTheHomeCurrency() {
        let app = launch(args: ["-seedConfirmForeign", "-presentScreen", "confirmManual"])
        let chip = app.buttons["manualFillUpCurrency_PLN"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "a foreign entry must show the chip row without a tap")
        XCTAssertFalse(app.buttons["manualFillUpCurrencyCollapsed"].exists)
        // And it must be VISIBLE, not merely present: a section that opens
        // itself below the fold has not opened in any sense that matters, which
        // is why a currency needing attention renders above the numbers card.
        XCTAssertTrue(chip.isHittable, "a foreign currency must be on screen without scrolling")
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

    func launchWithPrefill(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", seed]
        app.launch()
        return app
    }

    func openForm(_ app: XCUIApplication) {
        openManualForm(app)
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
        // And no PJ.17 caption: this seed carries no photo (the empty-but-alive
        // caption is for a scan that kept its photo).
        XCTAssertFalse(app.staticTexts["manualFillUpEmptyScanCaption"].exists)
        // The neutral, unlocked check line is up, exactly as on a manual form.
        XCTAssertTrue(app.staticTexts["manualFillUpCheckLine"].exists)

        // Save is off with nothing typed...
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].exists)

        // ...and the sheet is savable once the user types.
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        let liters = focusField(app, "manualFillUpLitersField")
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
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("20.00")
        let liters = focusField(app, "manualFillUpLitersField")
        liters.typeText("10")
        let price = focusField(app, "manualFillUpPricePerLField")
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
        //
        // Waited for, not asserted immediately: toggling rebuilds the save bar,
        // and a query landing mid-rebuild finds NO element at all - the failure
        // reads "No matches found for manualFillUpSaveButton", which looks like
        // a missing button rather than a momentary one. This is an expectation
        // on the real condition, not a sleep.
        // The mixed section now sits below the numbers card and the currency
        // row, so its toggles start under the pinned save bar. Scroll it into
        // the free region first - a tap on 825 pt of a 874 pt window lands on
        // the bar, not the switch.
        scrollClearOfSaveBar(app, coffee)
        coffee.tap()
        let twoExpenses = NSPredicate(format: "label CONTAINS %@", "2 expenses")
        expectation(for: twoExpenses, evaluatedWith: app.buttons["manualFillUpSaveButton"])
        waitForExpectations(timeout: 5)
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

// MARK: - P2.5 foreign currency

/// P2.5: detection comes from the extraction's currency (or the chip choice),
/// never the device locale. The conversion card shows the converted home amount
/// plus the rate and its date; a rate miss saves rate-pending (F9); a
/// low-confidence currency asks instead of converting; and the ordinary sheet
/// is unchanged when the currency matches home.
extension ConfirmManualUITests {

    func testForeignFillShowsTheConvertedAmountAndRate() {
        let app = launchWithPrefill("-seedConfirmForeign")
        openForm(app)

        // The conversion card renders with the worked number (289.50 PLN /
        // 4.2706 = 67.79 EUR) and the rate line names the pair, source and date.
        XCTAssertTrue(app.otherElements["manualFillUpConversionCard"].waitForExistence(timeout: 5))
        let value = app.staticTexts["manualFillUpConvertedValue"]
        XCTAssertTrue(value.exists)
        XCTAssertTrue(value.label.contains("67.79"), "converted value was '\(value.label)'")
        let rateLine = app.staticTexts["manualFillUpRateLine"]
        XCTAssertTrue(rateLine.exists)
        XCTAssertTrue(rateLine.label.contains("4.2706"), "rate line was '\(rateLine.label)'")
        XCTAssertTrue(rateLine.label.contains("ECB"))
    }

    func testForeignFillWithoutRateIsRatePending() {
        let app = launchWithPrefill("-seedConfirmForeignPending")
        openForm(app)

        // No rate for 2020-01-01: the entry is rate-pending (F9) - the card
        // shows the "≈ –" placeholder and the pending hint, never a number.
        XCTAssertTrue(app.otherElements["manualFillUpConversionCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["manualFillUpPendingValue"].exists)
        XCTAssertTrue(app.staticTexts["manualFillUpPendingHint"].exists)
        XCTAssertFalse(app.staticTexts["manualFillUpConvertedValue"].exists)
    }

    func testLowConfidenceCurrencyAsksAndNeverConverts() {
        let app = launchWithPrefill("-seedConfirmForeignLowConfidence")
        openForm(app)

        // An uncertain currency shows the amber prompt and NO conversion card,
        // even though the seed pack has a rate for the pair on that date.
        XCTAssertTrue(app.staticTexts["manualFillUpCurrencyHint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which currency is this?"].exists)
        XCTAssertFalse(app.otherElements["manualFillUpConversionCard"].exists)
        XCTAssertFalse(app.staticTexts["manualFillUpConvertedValue"].exists)
    }

    func testHomeCurrencyShowsNoConversionCard() {
        let app = launchWithPrefill("-seedConfirmPrefill")
        openForm(app)

        // Currency matches home (EUR): the ordinary sheet, no conversion card.
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["manualFillUpConversionCard"].exists)
    }
}

// MARK: - P5.2b the manual rate (F9 next step, hard rule 13)

/// The rate-pending card's missing next step (docs/ERRORS.md -> Confirm: "Save
/// anyway (converts later) · enter rate manually"): the user can type a rate on
/// the card, it flips to converted with the Manual source in place, and the
/// rate is an OPTION, never a gate - Save works from the pending state without
/// one. The scroll is geometric (`scrollClearOfSaveBar`), because `isHittable`
/// does not model occlusion by the pinned save bar.
extension ConfirmManualUITests {

    /// The pending card offers its next step, and the next step is reachable
    /// and hittable - above the save bar's top, not merely reported hittable
    /// while sitting under it.
    func testPendingCardOffersTheManualRateNextStep() {
        let app = launchWithPrefill("-seedConfirmForeignPending")
        openForm(app)

        XCTAssertTrue(app.otherElements["manualFillUpConversionCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["manualFillUpPendingHint"].exists, "converts when online")
        XCTAssertTrue(app.staticTexts["manualFillUpPendingValue"].exists, "≈ – placeholder")
        XCTAssertFalse(app.staticTexts["manualFillUpConvertedValue"].exists)

        let field = app.textFields["manualFillUpManualRateField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "the pending card must offer its manual-rate next step")
        scrollClearOfSaveBar(app, field)
        XCTAssertTrue(field.isHittable, "the next step must be reachable, not merely present")
        field.tap()
    }

    /// Entering a rate flips the card from pending to converted IN PLACE, with
    /// the manual source visible: 289.50 PLN at 4.2706 -> 67.79 EUR, rate line
    /// "4.2706 zł/€ · Manual, ...".
    func testEnteringRateFlipsPendingCardToConvertedInPlace() {
        let app = launchWithPrefill("-seedConfirmForeignPending")
        openForm(app)

        XCTAssertTrue(app.otherElements["manualFillUpConversionCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["manualFillUpPendingValue"].exists)

        let field = app.textFields["manualFillUpManualRateField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        scrollClearOfSaveBar(app, field)
        field.tap()
        field.typeText("4.2706")

        let value = app.staticTexts["manualFillUpConvertedValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5),
                      "a typed rate must flip the pending card to converted in place")
        XCTAssertTrue(value.label.contains("67.79"), "converted value was '\(value.label)'")
        XCTAssertFalse(app.staticTexts["manualFillUpPendingValue"].exists)
        let rateLine = app.staticTexts["manualFillUpRateLine"]
        XCTAssertTrue(rateLine.exists)
        XCTAssertTrue(rateLine.label.contains("4.2706"), "rate line was '\(rateLine.label)'")
        XCTAssertTrue(rateLine.label.contains("Manual"),
                      "the manual source must be visible, got '\(rateLine.label)'")
    }

    /// Save still works from the pending state without entering a rate: the
    /// manual rate is an option, never a save-blocker (F9).
    func testPendingStateSavesWithoutEnteringARate() {
        let app = launchWithPrefill("-seedConfirmForeignPending")
        openForm(app)

        XCTAssertTrue(app.otherElements["manualFillUpConversionCard"].waitForExistence(timeout: 5))
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "a pending rate is an option, never a gate (F9)")

        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "Save must work from the pending state without a rate")
    }
}

// MARK: - PJ.14 the live odometer-delta caption

/// PJ.14: the "+N km since last" caption under the odometer is LIVE - it reacts
/// to what is typed and never blocks the save (an implausible odometer warns in
/// amber and the user decides, hard rule 13). The four states are decided in
/// core (`OdometerDelta`); these tests pin the live rendering and never-gated save.
extension ConfirmManualUITests {

    /// Launches with a clean database. The suite's other seeds leave extra fills
    /// at the max odometer, corrupting the caption's pace anchor; a reset gives
    /// the seed exactly one prior fill six days before the form's date - the
    /// pace math these assertions depend on.
    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase"]
        app.launch()
        return app
    }

    /// Replaces the odometer field's contents, keeping it focused across calls
    /// (a blur regroups the digits and can race the delete/type sequence).
    private func replaceOdometer(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["manualFillUpOdometerField"]
        if !app.keyboards.firstMatch.exists {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: current.count))
        }
        field.typeText(text)
    }

    private func waitForCaption(_ app: XCUIApplication, _ label: String) {
        let predicate = NSPredicate(format: "label == %@", label)
        let caption = app.staticTexts["manualFillUpOdometerCaption"]
        expectation(for: predicate, evaluatedWith: caption)
        waitForExpectations(timeout: 5)
    }

    func testOdometerCaptionUpdatesLiveWithTheTypedValue() {
        let app = launchClean()
        openManualForm(app)

        // The pre-fill equals the last known odometer (119 486): the neutral
        // equal caption, never amber (equal is a legitimate no-distance state).
        waitForCaption(app, "Same as last")

        // Typing a larger value flips it live to the positive delta.
        replaceOdometer(app, "120000")
        waitForCaption(app, "+514 km since last")

        // Typing below last known flips it to the backwards warn.
        replaceOdometer(app, "119000")
        waitForCaption(app, "Odometer went backwards – check it.")

        // A forward value whose implied daily rate exceeds the limit warns too
        // (10 514 km / 6 days = 1 752/day > the seeded 1 500).
        replaceOdometer(app, "130000")
        waitForCaption(app, "Daily pace over the limit – check it.")
    }

    func testOdometerWarnNeverBlocksTheSave() {
        let app = launchClean()
        openManualForm(app)

        // A backwards odometer puts the amber warn up...
        replaceOdometer(app, "119000")
        waitForCaption(app, "Odometer went backwards – check it.")

        // ...but the save bar never becomes disabled because of it: two numbers
        // typed, save works, and the entry lands (hard rule 13).
        // The odometer's number pad is up; drop it first - a follow-up tap on
        // another field while it is up does not reliably transfer focus on the
        // iOS 26 simulator (the tap lands, focus does not move, and the next
        // typeText fails with "no keyboard focus").
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        let liters = focusField(app, "manualFillUpLitersField")
        liters.typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "a warn caption must never gate the save")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
    }
}

// MARK: - PJ.17 the empty-but-alive Confirm (F1)
extension ConfirmManualUITests {
    func testEmptyScanWithPhotoFocusesTotalAndShowsCaption() {
        let app = launchWithPrefill("-seedConfirmPrefillEmptyPhoto")
        openForm(app)
        let caption = app.staticTexts["manualFillUpEmptyScanCaption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, "Couldn't read this one – type it, the photo stays attached.")
        // F1: keyboard up on Total - prove focus by typing with no tap.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "keyboard up on Total (F1)")
        let total = app.textFields["manualFillUpTotalField"]
        let deadline = Date().addingTimeInterval(5)
        while !total.isHittable && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        // PJ.17b: poll the caption to the settled state, never assert in a slide-in transient.
        while !caption.isHittable && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        XCTAssertTrue(caption.isHittable, "caption in frame, not below the fold")
        total.typeText("7")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "7")
    }

    func testTypedPathShowsNoEmptyScanCaption() {
        let app = launch()
        openManualForm(app)
        XCTAssertFalse(app.staticTexts["manualFillUpEmptyScanCaption"].exists)
    }
}

// MARK: - PJ.48 the quiet "Attach receipt" row (typed path)

/// The typed door is a peer (J3b): a quiet "Attach receipt" row, never shown
/// where a scan already carried a photo.
extension ConfirmManualUITests {

    func testAttachReceiptRowOnTheTypedPathOpensTheSourceChoice() {
        let app = launch()
        openManualForm(app)
        let row = app.buttons["confirmAttachReceiptRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        scrollClearOfSaveBar(app, row)
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
    }

    func testAttachReceiptRowHiddenWhenAScanCarriedAPhoto() {
        let app = launchWithPrefill("-seedConfirmPrefillEmptyPhoto")
        openForm(app)
        XCTAssertFalse(app.buttons["confirmAttachReceiptRow"].exists)
    }
}
