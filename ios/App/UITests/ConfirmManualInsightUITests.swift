import XCTest

/// The after-save insight (J3 → Done, PJ.15), on the Confirm suite's own
/// helpers: the toast prints the engine's figure for the segment the save
/// closed, in one localised phrase, and its tap lands on Trends.
@MainActor
extension ConfirmManualUITests {

    /// This file's own copies of the sheet's helpers: the originals in
    /// ConfirmManualUITests.swift are `private`, so a cross-file extension
    /// carries its own (the pattern ConfirmManualStationStampUITests uses).
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

    /// Replaces the odometer field's contents, keeping it focused across calls.
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

    /// A full tank 500 km after the seeded full tank closes one segment: 35 L
    /// over 500 km is 7.0, the only figure of the year and so its best. The
    /// toast prints that figure - the engine's, at the tile's precision - and
    /// its tap lands on Trends.
    private func saveFullTankClosingASegment(_ app: XCUIApplication, decimalSeparator: String = ".") {
        openManualForm(app)
        // The odometer first, while the form sits at its top: once a keypad
        // has scrolled the sheet, the odometer card lies under the header and
        // a tap there focuses nothing (the odometer tests edit it first too).
        replaceOdometer(app, "119986")
        let total = focusField(app, "manualFillUpTotalField")
        // The keypad offers the locale's separator (a RU keypad has no "."):
        // the field's sanitiser maps a comma to the model's dot.
        total.typeText("58\(decimalSeparator)80")
        let liters = focusField(app, "manualFillUpLitersField")
        liters.typeText("35")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
    }

    func testSaveShowsTheInsightToastAndItsTapOpensTrends() {
        let app = launch()
        saveFullTankClosingASegment(app)

        let toast = app.staticTexts["7.0 L/100km – best this year"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5),
                      "the after-save insight did not appear for a fill that closed a segment")
        app.buttons["deltaToast"].tap()
        XCTAssertTrue(app.staticTexts["trendsHeaderTitle"].waitForExistence(timeout: 5),
                      "the insight's tap must land on Trends")
    }

    func testSaveShowsTheInsightToastInRussian() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        saveFullTankClosingASegment(app, decimalSeparator: ",")

        // One full localised phrase (never a spliced value). The figure keeps
        // the form's pinned "." separator (`ManualFillUpFormat`).
        let toast = app.staticTexts["7.0 л/100 км – лучший результат в этом году"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5),
                      "the RU insight did not render as one localised phrase")

        // `-AppleLanguages` persists in UserDefaults; put English back for the
        // suites that follow.
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

}
