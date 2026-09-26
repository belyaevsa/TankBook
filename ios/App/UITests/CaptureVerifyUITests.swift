import XCTest

/// The capture verify screen: the photo with the numbers recognised from it,
/// checked and corrected before the entry opens. The recognition is seeded
/// (`FillUpScanTestSeed`) so each test asserts what the user sees, not what
/// Vision happens to read; the photo is a corpus fixture because the simulator
/// has no camera.
@MainActor
final class CaptureVerifyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts/receipt-011-samara-diesel-ru.png")
            .path
    }

    private func shoot(_ seed: String) -> XCUIApplication {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture), "the corpus fixture is missing: \(fixture)")
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-captureFixtureImage", fixture, seed]
        app.launch()
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "captureShutterButton never appeared")
        shutter.tap()
        XCTAssertTrue(app.buttons["captureVerifyContinueButton"].waitForExistence(timeout: 15),
                      "the shutter must open the verify screen")
        return app
    }

    private func value(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    private func waitForValue(_ app: XCUIApplication, _ identifier: String, _ expected: String) {
        let deadline = Date().addingTimeInterval(10)
        while value(app, identifier) != expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(value(app, identifier), expected)
    }

    /// The recognised numbers are on the verify screen beside the photo, and a
    /// correction made there is what the entry opens with.
    func testTheRecognisedNumbersShowAndACorrectionReachesTheEntry() {
        let app = shoot("-seedFillUpScan")
        XCTAssertTrue(app.images["captureVerifyImage"].exists, "the photo is shown beside the numbers")
        waitForValue(app, "captureVerifyVolumeField", "42.30")
        waitForValue(app, "captureVerifyTotalField", "71.02")

        let total = app.textFields["captureVerifyTotalField"]
        total.tap()
        total.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        total.typeText(XCUIKeyboardKey.delete.rawValue)
        total.typeText("72.00")
        app.buttons["captureVerifyContinueButton"].tap()

        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "Continue opens the entry")
        XCTAssertEqual(value(app, "manualFillUpTotalField"), "72.00", "the corrected total reaches the entry")
        XCTAssertEqual(value(app, "manualFillUpLitersField"), "42.30", "the checked litres reach the entry")
    }

    /// A pump photo nothing was read from is admitted on the verify screen, and
    /// the entry does not repeat it.
    func testAPumpPhotoNothingWasReadFromIsAdmittedOnTheVerifyScreen() {
        let app = shoot("-seedFillUpScanPumpNothingRead")
        let admission = app.staticTexts["captureVerifyNothingRead"]
        XCTAssertTrue(admission.waitForExistence(timeout: 10))
        XCTAssertEqual(admission.label,
                       "Couldn't read the pump display – type the numbers from it, the photo stays attached.")
        XCTAssertFalse(labelled(app, "Read from the pump display").exists, "nothing read, so no alpha claim")
        app.buttons["captureVerifyContinueButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["manualFillUpEmptyScanCaption"].exists,
                       "the entry does not repeat what the verify screen said")
    }

    /// A doubtful pump pair carries its notices on the verify screen.
    func testADoubtfulPumpPairCarriesItsNoticesOnTheVerifyScreen() {
        let app = shoot("-seedFillUpScanPumpCaution")
        XCTAssertTrue(labelled(app, "Read from the pump display").waitForExistence(timeout: 10), "the alpha notice is on the verify screen")
        XCTAssertTrue(labelled(app, "a discount, or a misread").exists, "the price caution names the shown price")
        app.buttons["captureVerifyContinueButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10))
        XCTAssertFalse(labelled(app, "Read from the pump display").exists, "the entry does not repeat the alpha notice")
    }

    private func labelled(_ app: XCUIApplication, _ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// The photo zooms and turns: the controls are reachable and leave the
    /// photo and the actions in place.
    func testThePhotoZoomsAndTurns() {
        let app = shoot("-seedFillUpScan")
        for identifier in ["captureVerifyZoomIn", "captureVerifyZoomOut", "captureVerifyTurn"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, "\(identifier) must be reachable")
        }
        app.buttons["captureVerifyTurn"].tap()
        XCTAssertTrue(app.images["captureVerifyImage"].exists, "the turned photo is still shown")
        app.buttons["captureVerifyZoomIn"].tap()
        XCTAssertTrue(app.buttons["captureVerifyContinueButton"].isHittable, "zooming leaves the actions reachable")
    }
}
