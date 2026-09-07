import XCTest

/// P1.13b: the F9a conflict quote on the Confirm odometer card ("Aug 17 already
/// recorded 119 486 km.") must render the neighbour's odometer GROUPED through
/// the shared `OdometerFormat` (U+00A0 separator), never the raw digits - the
/// same class as P1.13, where a call site bypassed the correct shared
/// formatter. P1.13's own L4 could not catch this class: it compares FIELDS,
/// not the text inside a message. This asserts the RENDERED quote, in EN and RU
/// - a composer test only proves a string, and the user reads pixels. Kept in
/// their own suite because ConfirmManualUITests is at the file-length ceiling
/// (the ConfirmOdometerPrefillUITests precedent).
@MainActor
final class ConfirmF9aQuoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A clean database so the seed holds exactly one prior fill at the seeded
    /// odometer - the conflicting entry the F9a quote names. `miles` seeds the
    /// imperial variant (RV.126): the same prior fill, on a miles-configured
    /// car, so the quote must name miles and never kilometres.
    private func launchClean(russian: Bool = false, miles: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase"]
        if miles {
            app.launchArguments += ["-seedVehicleMiles"]
        }
        if russian {
            app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launch()
        return app
    }

    private func openManualForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    /// Replaces the odometer field's contents with a value BELOW the prior fill,
    /// keeping it focused (a blur regroups the digits and can race the sequence).
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

    func testF9aQuoteRendersTheGroupedNeighbourOdometer() {
        let app = launchClean()
        openManualForm(app)
        replaceOdometer(app, "119000")

        let warning = app.staticTexts["manualFillUpOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the F9a quote must render on the odometer card")
        XCTAssertTrue(warning.label.contains("119\u{00A0}486"),
                      "the quote must name the grouped neighbour, was '\(warning.label)'")
        XCTAssertFalse(warning.label.contains("119486"),
                       "the quote must not print the raw ungrouped figure, was '\(warning.label)'")
    }

    func testF9aQuoteRendersTheGroupedNeighbourOdometerInRussian() {
        let app = launchClean(russian: true)
        openManualForm(app)
        replaceOdometer(app, "119000")

        let warning = app.staticTexts["manualFillUpOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the F9a quote must render on the odometer card in Russian")
        XCTAssertTrue(warning.label.contains("119\u{00A0}486"),
                      "the RU quote must name the grouped neighbour, was '\(warning.label)'")
        XCTAssertFalse(warning.label.contains("119486"),
                       "the RU quote must not print the raw ungrouped figure, was '\(warning.label)'")
    }

    /// RV.126: the F9a quote used to hardcode `km` even when the vehicle is
    /// miles-configured - a miles driver was told about kilometres in the one
    /// message whose job is to make them trust the number they are correcting.
    /// A miles seed makes the rendered quote say `mi`, never `km`.
    func testF9aQuoteNamesMilesOnAMilesConfiguredCar() {
        let app = launchClean(miles: true)
        openManualForm(app)
        replaceOdometer(app, "74000")

        let warning = app.staticTexts["manualFillUpOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the F9a quote must render on the odometer card for a miles car")
        XCTAssertTrue(warning.label.contains("74\u{00A0}286 mi"),
                      "a miles car must be told about miles, was '\(warning.label)'")
        XCTAssertFalse(warning.label.contains("km"),
                       "a miles car must never be told about kilometres, was '\(warning.label)'")
    }

    func testF9aQuoteNamesMilesOnAMilesConfiguredCarInRussian() {
        let app = launchClean(russian: true, miles: true)
        openManualForm(app)
        replaceOdometer(app, "74000")

        let warning = app.staticTexts["manualFillUpOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5),
                      "the F9a quote must render on the odometer card in Russian for a miles car")
        XCTAssertTrue(warning.label.contains("74\u{00A0}286 миль"),
                      "the RU quote on a miles car must name miles, was '\(warning.label)'")
        XCTAssertFalse(warning.label.contains("км"),
                       "the RU quote on a miles car must never name kilometres, was '\(warning.label)'")
    }
}
