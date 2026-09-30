import XCTest

/// Drives the three ways in at a human pace while `simctl io recordVideo` films
/// the device, for the site's door-card recordings (docs/SITE.md -> "Motion").
/// Opt-in: skipped unless `TEST_RUNNER_SITE_RECORDING` is set, and it asserts
/// only that each step's screen arrives. Each test writes the host time at its
/// flow's start and end to `SITE_RECORDING_MARKS`, so the recording is trimmed
/// to the flow and nothing else.
final class SiteRecordingUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        try XCTSkipUnless(environment["SITE_RECORDING"] != nil, "site recordings are opt-in")
        continueAfterFailure = false
    }

    private var language: [String] {
        environment["SITE_RECORDING_LANG"] == "ru"
            ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
            : ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
    }

    private func mark(_ label: String) {
        guard let path = environment["SITE_RECORDING_MARKS"] else { return }
        let line = "\(label) \(Date().timeIntervalSince1970)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
        }
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The camera doors: the shutter, the verify screen reading the photo, a
    /// look at the numbers, Continue, and the form they filled.
    private func recordCapture(fixture: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-captureFixtureImage", fixture] + language
        app.launch()
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        // The first-run alpha notice is dismissible; the film shows a
        // returning user's capture screen.
        let notice = app.buttons["captureAlphaNoticeDismissButton"]
        if notice.waitForExistence(timeout: 2) { notice.tap() }
        pause(1.5)
        mark("start")
        pause(0.5)
        shutter.tap()
        let proceed = app.buttons["captureVerifyContinueButton"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 20))
        // The simulated camera's capture delay is not the app's speed: the film
        // keeps a moment of the capture screen before this mark and cuts the rest.
        mark("verify")
        // Continue only once the read has landed in the fields, then a look.
        let total = app.textFields["captureVerifyTotalField"]
        let expected = environment["SITE_RECORDING_TOTAL"] ?? ""
        let read = NSPredicate(format: "value CONTAINS %@", expected)
        let landed = expectation(for: read, evaluatedWith: total)
        wait(for: [landed], timeout: 20)
        // The model can hold the numbers before the screen draws them: wait
        // until no field still shows its reading spinner, then a look.
        let drawn = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.activityIndicators)
        wait(for: [drawn], timeout: 30)
        pause(3.0)
        proceed.tap()
        // The form sheet is in the accessibility tree while the verify screen
        // still covers it, so no query says when it is on screen: a fixed hold
        // covers the hand-off and leaves a look at the filled form.
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 30))
        pause(10.0)
        mark("end")
    }

    func testPumpDisplay() {
        recordCapture(fixture: environment["SITE_RECORDING_FIXTURE"] ?? "")
    }

    func testReceipt() {
        recordCapture(fixture: environment["SITE_RECORDING_FIXTURE"] ?? "")
    }

    /// The keyboard door: total, then litres, typed at a thumb's pace; the price
    /// per litre fills in and the cross-check locks.
    func testTyping() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "confirmManual"] + language
        app.launch()
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        pause(1.0)
        mark("start")
        pause(0.8)
        total.tap()
        pause(0.5)
        for key in "71.02" { total.typeText(String(key)); pause(0.16) }
        pause(0.5)
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        pause(0.5)
        for key in "42.30" { liters.typeText(String(key)); pause(0.16) }
        pause(3.0)
        mark("end")
    }
}
