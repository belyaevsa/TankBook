import XCTest

/// PJ.1 - the capture pipeline end to end: a real corpus image goes in through
/// either door (the shutter's frame or the Photos pick), through the RV.5
/// review step, and lands in the Confirm sheet with what Vision actually read.
/// No `-seedConfirmPrefill` anywhere: the values here come from the real
/// pipeline, or these tests prove nothing.
///
/// Split out of `CaptureUITests` when RV.5 pushed that file past its 700-line
/// limit. It is a clean seam, not a lint dodge: everything here needs a fixture
/// image and asserts recognition; nothing there does.
@MainActor
final class CapturePipelineUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func openCapture(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
    }

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads one by host path via
    /// `-captureFixtureImage` and OCRs it for real.
    private var fixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CaptureUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    /// The shutter takes a real frame (here the injected fixture - the
    /// simulator has no camera) and opens Confirm with the scan's litres
    /// pre-filled and dimmed. No `-seedConfirmPrefill`: the value must come
    /// from the real pipeline, or this test proves nothing.
    func testShutterOpensConfirmWithLitresPrefilledAndDimmed() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-captureFixtureImage", fixture])
        openCapture(app)

        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertTrue(shutter.isHittable, "the shutter must be tappable in fill-up mode")
        shutter.tap()

        // RV.5: the shutter now lands on the review step first; "Use this" is
        // what runs the pipeline and opens Confirm.
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the shutter must open the RV.5 review step")
        useThis.tap()

        let liters = app.textFields["manualFillUpLitersField"]
        XCTAssertTrue(liters.waitForExistence(timeout: 15),
                      "Use this must open the Confirm sheet")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "66.81",
                       "the scanned receipt's litres must be pre-filled")

        // Dimmed, never disabled: a scanned pre-fill is a default input that
        // stays fully editable (hard rule 13).
        XCTAssertTrue(liters.isEnabled, "a scanned pre-fill must never be read-only")

        // The crop evidence flowed through: the verify affordance is attached
        // to the resolved field.
        XCTAssertTrue(app.buttons["manualFillUpVerifyButton_volume"].waitForExistence(timeout: 5),
                      "the scanned litres must carry its crop for tap-to-verify")
    }

    /// The Photos door feeds the SAME path as the shutter: the injected
    /// fixture (the out-of-process picker cannot be driven) and the identical
    /// Confirm sheet opens.
    func testPhotosDoorFeedsTheSamePipeline() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-captureFixtureImage", fixture])
        openCapture(app)

        let photos = app.buttons["capturePhotosButton"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        photos.tap()

        // RV.5: the Photos door reviews the picked image exactly as the
        // shutter reviews the shot one - one review step, both doors.
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the Photos door must open the RV.5 review step")
        useThis.tap()

        let liters = app.textFields["manualFillUpLitersField"]
        XCTAssertTrue(liters.waitForExistence(timeout: 15),
                      "the Photos door must open the Confirm sheet")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "66.81",
                       "the Photos pick must pre-fill the same litres as the shutter")
    }

    /// Hard rule 15: a scan that resolves nothing opens the ordinary empty
    /// manual form, never an error (receipt-034 is that fixture).
    func testAResolvedNothingScanOpensTheEmptyFormNotAnError() {
        let fixture = fixturesRoot + "/receipts/receipt-034-lukoil-m11-ekto95-contract-zero-price-ru.jpeg"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-captureFixtureImage", fixture])
        openCapture(app)

        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "captureShutterButton never appeared")
        shutter.tap()

        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the shutter must open the RV.5 review step")
        useThis.tap()

        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 15),
                      "a nothing-resolved scan must still open the Confirm form")
        // Never an error state: no cross-check mismatch, no scan-failure hint.
        XCTAssertFalse(app.staticTexts["manualFillUpCrossCheckMismatch"].exists,
                       "a nothing-resolved scan must not render an error")
        XCTAssertFalse(app.staticTexts["manualFillUpNoVehicleHint"].exists,
                       "a nothing-resolved scan must not render an error")
        // The ordinary empty-form guidance is the only thing shown.
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].waitForExistence(timeout: 5),
                      "a nothing-resolved scan must render as the ordinary empty form")
    }
}
