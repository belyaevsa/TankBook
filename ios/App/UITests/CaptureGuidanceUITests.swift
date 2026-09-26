import XCTest

/// PU.40b - the detector on the live preview. With a pump fixture standing in
/// for the camera (`-captureCameraTestFrame`), the capture screen must tell the
/// user the display is in view before the shutter; with a receipt frame it must
/// leave the ordinary caption standing and never raise a hint. The shutter and
/// the manual door stay reachable in every state (hard rule 15).
@MainActor
final class CaptureGuidanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads one by host path.
    private var fixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CaptureGuidanceUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    /// A pump still the PU.38 measurement recorded as a fast-path display.
    private var pumpFixture: String {
        fixturesRoot + "/pump/pump-032-gilbarco-circlek-ee-clean.jpg"
    }

    private func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-powertrain", "ice", "-pumpTipSeen",
                               "-captureCameraTestFrame", fixture]
        app.launch()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
        return app
    }

    func testPumpFrameShowsDisplayInView() {
        let app = launch(fixture: pumpFixture)

        let caption = app.staticTexts["Display in view"]
        XCTAssertTrue(caption.waitForExistence(timeout: 60),
                      "a pump frame must report the display is in view")

        // The hint is a head start, never a gate: the shutter and the manual
        // door are still reachable (hard rule 15).
        XCTAssertTrue(app.buttons["captureShutterButton"].isEnabled,
                      "the shutter must never be disabled by the guidance state")
        XCTAssertTrue(app.buttons["captureTypeItButton"].isHittable,
                      "the manual door must stay reachable beside the hint")
    }

    func testReceiptFrameKeepsThePlainCaption() {
        let app = launch(fixture: fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png")

        let caption = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "detected automatically"))
            .firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 10),
                      "a receipt keeps the ordinary detection caption")
        XCTAssertFalse(app.staticTexts["Display in view"].exists,
                       "a receipt must not report a display in view")
        XCTAssertFalse(app.staticTexts["Move closer"].exists,
                       "a receipt must not raise the too-small hint")
        XCTAssertFalse(app.staticTexts["Tilt to show the whole display"].exists,
                       "a receipt must not raise the tilt hint")
    }
}
