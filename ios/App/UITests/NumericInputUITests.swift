import XCTest

/// P2.15: numeric fields filter letters and the locale separator at the
/// binding. `keyboardType` is a hint, not a constraint - a hardware keyboard
/// (the simulator), paste and dictation all bypass it - so these tests feed a
/// field exactly what a numberPad/decimalPad would NOT produce and assert the
/// value the model stores, which is the wiring the L1 sanitizer tests cannot
/// see. Kept in their own suite because the ConfirmManual suite is at the
/// file-length ceiling.
@MainActor
final class NumericInputUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase"]
        app.launch()
        return app
    }

    private func openManualForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    /// Bring a field above the pinned save bar, then tap it (the geometric
    /// scroll from ConfirmManualUITests - `isHittable` does not model the
    /// safeAreaInset overlay).
    private func focusField(_ app: XCUIApplication, _ identifier: String) {
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
    }

    /// Replaces the odometer's contents while it stays focused (a blur regroups
    /// the digits and can scroll the field out from under a re-tap).
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

    func testLettersTypedIntoTheOdometerAreFilteredAndSaved() {
        let app = launchClean()
        openManualForm(app)

        // "12a34" - the letter never reaches the model; the field keeps only
        // the digits, so nothing is silently dropped on save (hard rule 8).
        replaceOdometer(app, "12a34")
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField"), "1234",
                       "the odometer field must keep only digits, was \(fieldValue(app, "manualFillUpOdometerField"))")

        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }
        focusField(app, "manualFillUpTotalField")
        app.textFields["manualFillUpTotalField"].typeText("71.02")
        focusField(app, "manualFillUpLitersField")
        app.textFields["manualFillUpLitersField"].typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        // Read the stored odometer back from the newest entry: 1234 persisted,
        // never a nil odometer.
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let odometer = app.textFields["manualFillUpOdometerField"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        let stored = (odometer.value as? String) ?? ""
        XCTAssertEqual(stored.replacingOccurrences(of: "\u{00A0}", with: ""), "1234",
                       "the stored odometer must be 1234, was '\(stored)'")
    }

    func testDecimalFieldDropsLettersAndNormalisesTheComma() {
        let app = launchClean()
        openManualForm(app)

        // "4,2a7": the RU comma normalises to the pinned dot and the letter is
        // dropped, so the model holds 4.27. Type liters too, then assert the
        // DERIVED price - it is computed from the sanitized total, so it proves
        // the model, never the raw display. 4.27 / 42.30 = 0.101.
        focusField(app, "manualFillUpTotalField")
        app.textFields["manualFillUpTotalField"].typeText("4,2a7")
        focusField(app, "manualFillUpLitersField")
        app.textFields["manualFillUpLitersField"].typeText("42.30")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "0.101",
                       "the derived price must reflect the sanitized total 4.27, "
                           + "was \(fieldValue(app, "manualFillUpPricePerLField"))")
    }
}
