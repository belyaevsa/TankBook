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

    /// Scroll a number field clear of the keyboard and the pinned save bar,
    /// then tap it (the same helper `CaptureUITests` uses): the numbers card
    /// sits below Date/Odometer/Fuel, so a tap on a covered field misses
    /// silently and the `typeText` that follows fails as if the field were
    /// broken.
    @discardableResult
    private func focusNumberField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if field.isHittable && field.frame.maxY < barTop - 8 { break }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { break }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
        return field
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

    /// RV.12: saving a captured entry must LEAVE capture. The capture screen is
    /// a modal over the tab the user was on, and the Confirm sheet's own
    /// `dismiss()` only uncovers the camera again - so a completed entry looked
    /// exactly like a failed one, and a second tap started a second entry.
    ///
    /// The assertions are ordered so none of them can pass for free: the camera
    /// surface is proven present BEFORE the save, the Save button is proven
    /// ENABLED before it is tapped (a tap on a disabled button does nothing and
    /// everything after it passes for the wrong reason), and only then is the
    /// shutter's absence evidence of anything.
    func testSavingAScannedEntryLeavesCaptureInsteadOfUncoveringTheCamera() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-captureFixtureImage", fixture])
        openCapture(app)

        // Before: the camera surface is what the user is looking at, and the
        // tab underneath is covered.
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10),
                      "the camera surface must be on screen before the save")
        // `exists` is NOT the check here: XCUITest still reports the covered
        // tab's elements as existing under a `fullScreenCover`, so an
        // existence assertion on Home passes whether or not the modal was ever
        // torn down. Hit-testing is what tells the two apart.
        XCTAssertFalse(app.staticTexts["homeHeaderTitle"].isHittable,
                       "the capture modal must cover the tab it was opened from")

        shutter.tap()
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the shutter must open the RV.5 review step")
        useThis.tap()

        // The scan pre-fills litres; Save needs total as well, so type it.
        XCTAssertTrue(app.textFields["manualFillUpLitersField"].waitForExistence(timeout: 15),
                      "Use this must open the Confirm sheet")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the save bar never appeared")
        if !save.isEnabled {
            focusNumberField(app, "manualFillUpTotalField").typeText("4013.10")
        }
        XCTAssertTrue(save.isEnabled,
                      "Save must be enabled - a tap on a disabled button saves nothing")
        save.tap()

        // After: back on the tab the entry was started from, with the camera
        // gone. The Confirm sheet being gone proves nothing (that always
        // worked) - the shutter's absence is the assertion that pins RV.12.
        let home = app.staticTexts["homeHeaderTitle"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        // Hittable, not merely existing: the covered tab exists throughout.
        let landed = expectation(for: NSPredicate(format: "isHittable == true"),
                                 evaluatedWith: home)
        XCTAssertEqual(XCTWaiter().wait(for: [landed], timeout: 10), .completed,
                       "a saved capture must land back on the tab it started from")
        XCTAssertFalse(app.buttons["captureShutterButton"].exists,
                       "saving a captured entry must not drop the user back in the camera")
        XCTAssertFalse(app.buttons["captureCloseButton"].exists,
                       "the capture modal must be torn down, not merely uncovered")
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
