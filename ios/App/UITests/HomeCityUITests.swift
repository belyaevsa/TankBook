import XCTest

/// The car's home city (docs/SCHEMA.md -> Vehicle.homeCity) and the tire set's
/// season: the one-time question on Home after the first scanned receipt, the
/// picker, the details row, and the season chips.
@MainActor
final class HomeCityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-homeResetDatabase"] : []) + ["-seedSettingsSignedIn",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_EE"] + args
        app.launch()
        return app
    }

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testConfirmingTheReceiptsCitySavesItOnTheCar() {
        let app = launch(["-seedHomeCityQuestion"])
        let yes = app.buttons["homeCityAskYes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "the first scanned receipt's city is offered")
        XCTAssertTrue(yes.label.contains("Tallinn"), yes.label)
        yes.tap()
        XCTAssertTrue(anyElement(app, "homeCityAskTitle").waitForNonExistence(timeout: 5), "answered once, gone")
        app.terminate()

        let details = launch(["-presentScreen", "vehicleDetail"], reset: false)
        let row = details.buttons["vehicleDetailHomeCity"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Tallinn"), "the car keeps the city: \(row.label)")
        XCTAssertFalse(anyElement(details, "homeCityAskTitle").exists)
    }

    func testNotNowPutsTheQuestionAway() {
        let app = launch(["-seedHomeCityQuestion"])
        let notNow = app.buttons["homeCityAskNotNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        notNow.tap()
        XCTAssertTrue(anyElement(app, "homeCityAskTitle").waitForNonExistence(timeout: 5))
        app.terminate()
        let again = launch([], reset: false)
        XCTAssertTrue(anyElement(again, "homeOdometer").waitForExistence(timeout: 10))
        XCTAssertFalse(anyElement(again, "homeCityAskTitle").exists, "Not now is remembered")
    }

    /// A receipt with no city asks with the picker; the picker finds a city by
    /// prefix and the car keeps it.
    func testChoosingACityThroughThePicker() {
        let app = launch(["-seedHomeCityQuestionNoCity"])
        let choose = app.buttons["homeCityAskChoose"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["homeCityAskYes"].exists, "nothing to confirm without a receipt city")
        choose.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tar")
        let tartu = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Tartu")).firstMatch
        XCTAssertTrue(tartu.waitForExistence(timeout: 5))
        tartu.tap()
        XCTAssertTrue(anyElement(app, "homeCityAskTitle").waitForNonExistence(timeout: 5))
    }

    /// The whole path: a real receipt through the real capture, saved, raises
    /// the question with the city that receipt printed; a typed fill-up does not.
    func testTheFirstScannedReceiptAsksWithItsCity() {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts/receipt-054-circlek-tallinn-95-et.jpg")
            .path
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture))
        let app = launch(["-seedVehicleForUITests", "-inboxReset", "-presentScreen", "capture",
                          "-cameraStatus", "authorized", "-captureFixtureImage", fixture])
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        let useThis = app.buttons["captureVerifyContinueButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 20))
        useThis.tap()
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled, "the scan filled enough to save")
        save.tap()
        let yes = app.buttons["homeCityAskYes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "the first scanned receipt asks where the car is kept")
        XCTAssertTrue(yes.label.contains("Tallinn"), yes.label)
    }

    func testATypedFillUpDoesNotAsk() {
        let app = launch(["-seedVehicleForUITests", "-presentScreen", "confirmManual"])
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        total.tap()
        total.typeText("70")
        app.textFields["manualFillUpLitersField"].tap()
        app.textFields["manualFillUpLitersField"].typeText("40")
        app.buttons["manualFillUpSaveButton"].tap()
        XCTAssertTrue(anyElement(app, "homeOdometer").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["homeCityAskYes"].exists)
        XCTAssertFalse(app.buttons["homeCityAskChoose"].exists, "only a scanned receipt raises the question")
    }

    func testTheSeasonIsSetOnATireSet() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedTireSets", "-presentScreen", "tireSets",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let set = app.staticTexts["Winter Nokian"]
        XCTAssertTrue(set.waitForExistence(timeout: 10))
        set.tap()
        let winter = app.buttons["tireSeason_winter"]
        XCTAssertTrue(winter.waitForExistence(timeout: 10))
        XCTAssertFalse(winter.isSelected)
        winter.tap()
        XCTAssertTrue(winter.isSelected)
        app.buttons["tireSetSaveButton"].tap()
        XCTAssertTrue(set.waitForExistence(timeout: 10))
        set.tap()
        XCTAssertTrue(app.buttons["tireSeason_winter"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tireSeason_winter"].isSelected, "the season was saved")
    }
}
