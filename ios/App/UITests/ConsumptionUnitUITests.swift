import XCTest

/// RV.296 - a car set to MPG reads MPG figures, not L/100km numbers under an
/// MPG label. The full-history seed's headline is 5.25 L/100km; on the miles
/// car the hero, the Trends tile and the Log rows print the MPG conversion
/// (235.215 / 5.2525 = 44.8) beside the MPG label.
@MainActor
final class ConsumptionUnitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", "-seedHomeFullHistory", "-seedHomeMiles"]
            + (russian ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] : [])
        app.launch()
        return app
    }

    func testTheMilesCarReadsMPGOnHomeAndTrends() {
        let app = launch()
        let hero = app.staticTexts["homeHeadlineValue"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        // The hero's label is its VoiceOver phrase: the figure, then the spoken unit.
        XCTAssertTrue(hero.label.hasPrefix("44.8 "),
                      "the hero must be the MPG conversion of 5.25 L/100km, not 5.3: \(hero.label)")
        XCTAssertFalse(app.staticTexts["5.3"].exists, "the L/100km figure must not appear under an MPG label")

        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trendsConsumptionTile"].waitForExistence(timeout: 10))
        // The tile's figure label is its VoiceOver phrase: figure, unit, trend.
        let labels = app.staticTexts.matching(identifier: "trendsConsumptionTile").allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.hasPrefix("44.8 ") }, "the Trends tile reads the same MPG figure: \(labels)")
    }

    func testTheMilesCarReadsMPGInRussian() {
        let app = launch(russian: true)
        let hero = app.staticTexts["homeHeadlineValue"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        XCTAssertTrue(hero.label.hasPrefix("44.8 "), hero.label)
    }
}
