import XCTest

/// AdBlue is never fuel. A diesel car's manual form offers an AdBlue
/// chip that saves a top-up; Home's car card shows the last top-up and the
/// rate (a dash until two exist); Trends shows the rate at the second top-up.
/// The seeds are `P114HomeTestSeed` (8 L over 2200 km = 3.6 L/1000 km).
@MainActor
final class AdBlueUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
        app.launch()
        return app
    }

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testOneTopUpShowsTheLineWithADashAndNoTrendsCard() {
        let app = launch(["-seedHomeAdBlueOne"])
        let line = anyElement(app, "homeAdBlueLine")
        XCTAssertTrue(line.waitForExistence(timeout: 10), "a car with a top-up shows the AdBlue line")
        XCTAssertTrue(line.label.contains("8.00"), "the line names the last top-up: \(line.label)")
        XCTAssertTrue(line.label.contains("–"), "one top-up has no rate - a dash, never an estimate: \(line.label)")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(line.frame), "the line sits inside the window")

        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(anyElement(app, "trendsConsumptionTile").waitForExistence(timeout: 10))
        XCTAssertFalse(anyElement(app, "trendsAdBlueCard").exists, "no Trends card before the second top-up")
    }

    func testTwoTopUpsShowTheRateOnHomeAndTrends() {
        let app = launch(["-seedHomeAdBlueTwo"])
        let line = anyElement(app, "homeAdBlueLine")
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(line.label.contains("3.6"), "8 L over 2200 km is 3.6 L/1000 km: \(line.label)")

        app.buttons["tabbar.trends"].tap()
        let card = anyElement(app, "trendsAdBlueCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the second top-up brings the Trends card")
        XCTAssertTrue(card.label.contains("3.6"), card.label)
    }

    func testACarWithoutAdBlueShowsNoLine() {
        let app = launch(["-seedHomeRV152"])
        XCTAssertTrue(anyElement(app, "homeOdometer").waitForExistence(timeout: 10))
        XCTAssertFalse(anyElement(app, "homeAdBlueLine").exists)
    }

    /// The typed door (hard rule 15): a diesel car's form offers AdBlue beside
    /// diesel; choosing it hides the tank rows and saves a top-up Home shows.
    func testTheDieselFormSavesAnAdBlueTopUp() {
        let app = launch(["-seedVehicleForUITests", "-seedVehicleDieselOnly", "-presentScreen", "confirmManual"])
        let chip = app.buttons["manualFillUpAdBlueChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "a diesel car is offered AdBlue")
        XCTAssertTrue(app.switches["manualFillUpIsFullToggle"].exists)
        chip.tap()
        XCTAssertFalse(app.switches["manualFillUpIsFullToggle"].exists, "a top-up has no full-tank state")

        app.textFields["manualFillUpTotalField"].tap()
        app.textFields["manualFillUpTotalField"].typeText("8.99")
        app.textFields["manualFillUpLitersField"].tap()
        app.textFields["manualFillUpLitersField"].typeText("10")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.label.contains("AdBlue"), "the save bar says what it writes: \(save.label)")
        save.tap()

        let line = anyElement(app, "homeAdBlueLine")
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the saved top-up reaches the car card")
        XCTAssertTrue(line.label.contains("10.00"), line.label)
    }

    func testAPetrolCarIsNotOfferedAdBlue() {
        let app = launch(["-seedVehicleForUITests", "-presentScreen", "confirmManual"])
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["manualFillUpAdBlueChip"].exists)
    }
}
