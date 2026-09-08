import XCTest

// MARK: - RV.145 the Trends spend tile inherits the currency-carrying total

/// Kept as an extension of `TrendsUITests` (its own file, so the base file
/// stays under the lint ceiling) - the tests run as part of the Trends suite.
///
/// RV.145 fixed the shared classifier, so the Trends spend tile - which reduces
/// through the same `HomeStats.monthSpend` as Home's divider and vitals tile -
/// shows the current month's figure with the currency it is denominated in, and
/// a month whose known figures span two home currencies prints the per-currency
/// breakdown, never a bare sum.
@MainActor
extension TrendsUITests {

    /// Trends' own `launch` is private to its base file; these extensions need
    /// the same deterministic launch (reset, Trends tab, EN, seed).
    private func launchRV145(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-selectTrendsTab",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
        app.launch()
        return app
    }

    /// The owner's USD car with EUR-homed rows: the Trends spend tile states
    /// the euro month in euros - the same defect surface Home showed, reached
    /// through the Trends tab.
    func testRV145TrendsSpendTileStatesAnEURMonthInEuros() {
        let app = launchRV145(args: ["-seedHomeRV145Owner"])

        let tileValue = app.staticTexts.matching(identifier: "trendsSpendTile")
            .matching(NSPredicate(format: "label CONTAINS %@", "€")).firstMatch
        XCTAssertTrue(tileValue.waitForExistence(timeout: 15),
                      "the current month has spend, so the spend tile must render")
        XCTAssertFalse(tileValue.label.contains("$"),
                       "no dollar may appear on the euro month's tile: \(tileValue.label)")
    }

    /// A mixed-currency current month renders its per-currency breakdown on the
    /// spend tile - never a single number that is not a quantity of anything.
    func testRV145TrendsSpendTileShowsTheBreakdownForAMixedMonth() {
        let app = launchRV145(args: ["-seedHomeRV145Mixed"])

        let tileValue = app.staticTexts.matching(identifier: "trendsSpendTile")
            .matching(NSPredicate(format: "label CONTAINS %@", "$")).firstMatch
        XCTAssertTrue(tileValue.waitForExistence(timeout: 15))
        XCTAssertTrue(tileValue.label.contains("€") && tileValue.label.contains("$"),
                      "a mixed month must list both currencies on the spend tile: \(tileValue.label)")
    }
}
