import XCTest

/// RV.118 - the headline says what it is made of. The NUMBERS are asserted,
/// not the line's existence: the full-history seed has five full-tank fills
/// inside the 90-day window (the sixth sits exactly on the edge, before it),
/// so the line reads "5 fills · last 90 days · 5 full tanks" on Home and on
/// the Trends consumption tile, in EN and RU; a car with fills but no closed
/// segment reads "Not enough data yet" with the count it has.
@MainActor
final class HeadlineProvenanceUITests: XCTestCase {

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

    func testHomeAndTrendsNameTheFillsTheWindowAndTheFullTanks() {
        let app = launch(["-seedHomeFullHistory"])
        let line = app.staticTexts["homeHeadlineProvenance"]
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the headline carries its provenance line")
        XCTAssertEqual(line.label, "5 fills · last 90 days · 5 full tanks")

        app.buttons["tabbar.trends"].tap()
        let tile = app.descendants(matching: .any)["trendsConsumptionTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["5 fills · last 90 days · 5 full tanks"].waitForExistence(timeout: 5),
                      "Trends reads the same line off the same derivation")
    }

    func testTheLineIsAWholeRussianPhrase() {
        let app = launch(["-seedHomeFullHistory"], russian: true)
        let line = app.staticTexts["homeHeadlineProvenance"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(line.label, "5 заправок · за последние 90 дней · 5 с полным баком")
    }

    func testUnderTheFloorTheLineSaysNotEnoughDataWithTheCount() {
        let app = launch(["-seedHomeSingleFill"])
        let line = app.staticTexts["homeHeadlineProvenance"]
        XCTAssertTrue(line.waitForExistence(timeout: 10), "a car under the floor still says what it has")
        XCTAssertEqual(line.label, "Not enough data yet · 1 fill · 1 full tank")
        XCTAssertFalse(app.staticTexts["homeHeadlineValue"].exists, "never a computed average under the floor")
    }
}
