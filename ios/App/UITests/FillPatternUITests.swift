import XCTest

/// RV.120 - the fill pattern card. The seeded pattern is exact (500 km every
/// 10 days, 625 km of range on a corroborated 50 L tank); the forecast is
/// expected only when the launch date allows one and is then the stated
/// arithmetic; a car whose catalog tank no fill ever corroborated shows the
/// spacing and NO range - omitted, never zeroed - in EN and RU.
@MainActor
final class FillPatternUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String], russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"]
            + (russian ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] : []) + arguments
        app.launch()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !element.exists, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }

    /// The forecast the seed implies for today: the in-month fills' 50 € each,
    /// scaled from the day of month to the month - or nil before day 7 / with
    /// fewer than two fills in the month.
    private func expectedForecast() -> String? {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let month = calendar.dateInterval(of: .month, for: now)!
        let inMonth = [40, 30, 20, 10].map { now.addingTimeInterval(-Double($0) * 86_400) }
            .filter { month.contains($0) }.count
        guard day >= 7, inMonth >= 2 else { return nil }
        let amount = (Double(inMonth) * 50.0 / Double(day) * Double(daysInMonth)).rounded()
        return "≈ \(Int(amount))\u{00A0}€"
    }

    /// `.firstMatch` throughout: the tab bar keeps Trends' copy of the card in
    /// the hierarchy beside Home's, and both read the same derivation.
    private func steadyPattern(russian: Bool) {
        let app = launch(["-seedHomeFillPattern"], russian: russian)
        let card = app.descendants(matching: .any)["homeFillPatternCard"]
        scrollTo(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10), "a car over the floor shows the card")
        XCTAssertEqual(app.staticTexts["homeFillPatternBetween"].firstMatch.label, russian ? "500 км" : "500 km")
        XCTAssertTrue(app.staticTexts[russian ? "каждые 10.0 дн." : "every 10.0 days"].exists)
        XCTAssertEqual(app.staticTexts["homeFillPatternRange"].firstMatch.label, russian ? "625 км" : "625 km")
        XCTAssertTrue(app.staticTexts[russian ? "на баке 50 л" : "on a 50 L tank"].exists,
                      "the range names the tank it was built on")
        if let forecast = expectedForecast() {
            XCTAssertEqual(app.staticTexts["homeFillPatternForecast"].firstMatch.label, forecast,
                           "the forecast is the stated arithmetic - spend so far scaled to the month")
        } else {
            XCTAssertFalse(app.staticTexts["homeFillPatternForecast"].exists,
                           "too early in the month, or too few fills: no forecast rather than a guess")
        }
    }

    func testTheSteadyPatternReadsItsExactFigures() {
        steadyPattern(russian: false)
    }

    func testTheSteadyPatternReadsItsExactFiguresInRussian() {
        steadyPattern(russian: true)
    }

    /// The full-history seed's 71 L catalog tank was never filled past 43.5 L:
    /// the spacing shows, the range is omitted.
    func testAnUncorroboratedTankShowsNoRange() {
        let app = launch(["-seedHomeFullHistory"])
        let card = app.descendants(matching: .any)["homeFillPatternCard"]
        scrollTo(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["homeFillPatternBetween"].exists)
        XCTAssertFalse(app.staticTexts["homeFillPatternRange"].exists,
                       "a range built on a catalog capacity nobody corroborated is not shown")
    }

    func testUnderTheFloorThereIsNoCard() {
        let app = launch(["-seedHomeSingleFill"])
        XCTAssertTrue(app.staticTexts["homeD4Hint"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["homeFillPatternCard"].exists)
    }
}
