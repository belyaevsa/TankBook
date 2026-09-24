import XCTest

/// The Capture Lab, a beta experiment. The lab is reached from About's
/// Experiments row, shows seven presets and a shutter, and one press shoots the same scene under
/// every preset and renders a results table with seven rows. The simulator has
/// no camera, so `-captureCameraTestFrame` supplies the frame the run shoots.
@MainActor
final class CaptureLabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads one by host path.
    private var fixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CaptureLabUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    /// The About screen's DEBUG row sits below the tall feedback composer, so
    /// it can be off-screen at launch; scroll it above the owned tab bar before
    /// tapping. `isHittable` alone lies about an element under the bar.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while element.frame.midY > 700 || !element.isHittable, attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Open the lab from About, confirm the seven presets and the shutter, press
    /// the shutter and read the results table back: seven rows, one per preset.
    func testLabShootsEveryPresetAndShowsSevenResults() {
        let fixture = fixturesRoot + "/pump/pump-007-lukoil-spb-comma-decimals-ru.png"
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", "about",
                               "-captureCameraTestFrame", fixture]
        app.launch()

        let row = app.buttons["captureLabRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "the DEBUG Capture lab row must render on About")
        scrollUntilHittable(row, in: app)
        row.tap()

        let shutter = app.buttons["captureLabShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10),
                      "the lab must open with its shutter")

        let presets = ["default", "quality", "speed", "metered", "locked", "zoom2x", "high1080"]
        for preset in presets {
            XCTAssertTrue(app.switches["captureLabPreset-\(preset)"].exists,
                          "preset \(preset) must be offered")
        }

        shutter.tap()

        // The run appends rows in preset order, so the LAST preset's row is the
        // run's completion signal - waiting on the first row would count a
        // half-finished table.
        let lastResult = app.staticTexts["captureLabResult-high1080"]
        XCTAssertTrue(lastResult.waitForExistence(timeout: 180),
                      "the run must shoot every preset and render the table")
        let rows = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'captureLabResult-'"))
        XCTAssertEqual(rows.count, 7, "the results table must have one row per preset")
        for preset in presets {
            XCTAssertTrue(app.staticTexts["captureLabResult-\(preset)"].exists,
                          "the results table must carry the \(preset) row")
        }
    }
}
