import XCTest

/// RV.222 + RV.223 - the capture surface's two recovery paths. Both are
/// behaviours a comment promised and the code beneath it did not keep: a grant
/// in Settings did not restart the session, and a camera fault was a silent
/// no-op. Split out of `CaptureUITests`, which is at its file-length limit.
@MainActor
final class CaptureRecoveryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads one by host path.
    private var fixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CaptureRecoveryUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    // MARK: - RV.222: a grant in Settings resumes the session

    /// The F8 payoff: launching denied, then returning from Settings with the
    /// camera granted, must resume the camera surface without a relaunch - and
    /// the session must actually be RUNNING, not merely the status flipped.
    /// `-cameraStatusSequence denied,authorized` models the Settings round-trip
    /// on the second `status()` read (the scenePhase handler's), and
    /// `-captureCameraTestFrame` makes `CameraController.start()` observable on
    /// a simulator with no camera - the fixture double would bypass `capture()`
    /// and could not tell a started session from an unstarted one.
    func testGrantOnReturnFromSettingsResumesTheSessionWithoutRelaunch() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture",
                                "-cameraStatusSequence", "denied,authorized",
                                "-captureCameraTestFrame", fixture])

        // Precondition: denied at launch, so the permission card is up and the
        // shutter is not.
        XCTAssertTrue(app.buttons["capturePermissionSettingsButton"].waitForExistence(timeout: 10),
                      "the denied state must be up before the Settings round-trip")
        XCTAssertFalse(app.buttons["captureShutterButton"].exists,
                       "a denied capture surface must not offer the shutter")

        // Model the Settings round-trip: background, then foreground. The
        // scenePhase handler re-reads the status and, when it is now
        // authorised, starts the session.
        XCUIDevice.shared.press(.home)
        app.activate()

        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10),
                      "a grant on return must resume the camera surface, no relaunch")
        shutter.tap()
        XCTAssertTrue(app.buttons["captureReviewUseButton"].waitForExistence(timeout: 10),
                      "the resumed session must hand back a frame, not a blank preview")
    }

    // MARK: - RV.223: a camera fault surfaces its next step

    /// A real camera that returns nil (in use, or a hardware fault) must show
    /// the fault card, and its control must actually reach the manual form -
    /// not merely render a label. `-cameraStatus authorized` with no fixture and
    /// no simulated frame is the simulator's hardware-absence fault, which is
    /// the same nil the real path returns.
    func testCameraFaultShowsTheCardAndTypeItReachesTheManualForm() {
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized"])
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "captureShutterButton never appeared")
        shutter.tap()

        XCTAssertTrue(app.staticTexts["The camera didn't respond – type the entry instead."]
            .waitForExistence(timeout: 10),
                      "a nil capture must surface the fault card, never silence")
        XCTAssertFalse(app.buttons["capturePermissionSettingsButton"].exists,
                       "a hardware fault must not name Settings - Settings cannot fix it")

        let typeIt = app.buttons["captureFaultTypeItButton"]
        XCTAssertTrue(typeIt.exists, "the fault card must carry its next-step control")
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "the fault card's next step must reach the manual form")
    }
}
