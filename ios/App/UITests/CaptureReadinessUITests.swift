import XCTest

/// PJ.16 - the capture screen's readiness hints and torch. The simulator has no
/// camera, so the signals are injected: `-captureHintsEnabled` turns the hints
/// on, `-captureHintLuma` stands in for the preview's brightness and
/// `-captureFakeTorch` for a device with a torch. "Type it" must stay reachable
/// under every hint (hard rule 15).
@MainActor
final class CaptureReadinessUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests", "-presentScreen", "capture",
                               "-cameraStatus", "authorized", "-alphaNoticeReset", "-captureHintsEnabled"] + extra
        app.launch()
        return app
    }

    private func assertTypeItReachable(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.exists, "Type it must stay on screen", file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(typeIt.frame),
                      "Type it must sit inside the window", file: file, line: line)
    }

    func testADarkPreviewOffersTheTorchAndKeepsTypeIt() {
        let app = launch(["-captureHintLuma", "0.05", "-captureFakeTorch"])
        let hint = app.buttons["captureDarkHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "a dark preview offers the torch")
        assertTypeItReachable(app)
        hint.tap()
        let toggle = app.buttons["captureTorchToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "on", "the hint turns the torch on")
        XCTAssertFalse(app.buttons["captureDarkHint"].exists, "with the torch on, the dark hint steps aside")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "off")
    }

    func testABrightPreviewShowsNoDarkHint() {
        let app = launch(["-captureHintLuma", "0.6", "-captureFakeTorch"])
        XCTAssertTrue(app.buttons["captureTorchToggle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["captureDarkHint"].waitForExistence(timeout: 2))
    }

    func testNothingInFrameOffersTypeItAfterAWhile() {
        let app = launch([])
        let hint = app.otherElements["captureFillHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "nothing detected for a while offers the manual door")
        assertTypeItReachable(app)
        app.buttons["captureFillHintTypeIt"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "the hint's Type it opens the manual form")
    }

    /// The torch's state is remembered for the next capture.
    func testTheTorchIsRemembered() {
        var app = launch(["-captureFakeTorch"])
        let toggle = app.buttons["captureTorchToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "on" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "on")
        app.terminate()
        app = launch(["-captureFakeTorch"])
        let again = app.buttons["captureTorchToggle"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(again.value as? String, "on", "the torch preference survives a relaunch")
        again.tap()
        XCTAssertEqual(again.value as? String, "off")
    }
}
