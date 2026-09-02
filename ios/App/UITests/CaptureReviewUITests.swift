import XCTest

/// RV.5 - the capture review step. Reported from a device walk: a shot was
/// taken and the flow moved straight on with nothing shown, so the user could
/// neither see the frame nor refuse it.
///
/// Every test here sets `-captureFixtureImage`: the simulator has no camera,
/// so without it the shutter exercises the permission surface and proves
/// nothing about this feature. The assertions are about BEHAVIOUR, not about
/// an identifier existing - "Re-take" is asserted by what it leaves on screen
/// (the live capture surface) and by what it does NOT present (Confirm).
@MainActor
final class CaptureReviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CaptureReviewUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")
            .appendingPathComponent("receipt-011-samara-diesel-ru.png")
            .path
    }

    private func launchCapture() -> XCUIApplication {
        // A missing fixture would silently fall through to the (absent)
        // simulator camera and the shutter would do nothing at all - a failure
        // that reads like the feature is broken. Fail on the real cause.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture),
                      "the corpus fixture is missing: \(fixture)")
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-captureFixtureImage", fixture]
        app.launch()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
        return app
    }

    private func shoot(_ app: XCUIApplication) {
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "captureShutterButton never appeared")
        shutter.tap()
    }

    // MARK: - The step exists, with the photo and both verdicts

    /// The photo is shown, and both verdicts are reachable. The image element
    /// is asserted too: a review with the buttons but no picture answers
    /// nothing about legibility, which is the whole point of the step.
    func testAShotShowsThePhotoWithBothVerdictsReachable() {
        let app = launchCapture()
        shoot(app)

        let image = app.images["captureReviewImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 15),
                      "the shot must be shown before anything is read from it")
        XCTAssertGreaterThan(image.frame.height, 200,
                             "the photo must be large enough to read a total on")

        let useThis = app.buttons["captureReviewUseButton"]
        let retake = app.buttons["captureReviewRetakeButton"]
        XCTAssertTrue(useThis.exists && useThis.isHittable, "Use this must be reachable")
        XCTAssertTrue(retake.exists && retake.isHittable, "Re-take must be reachable")

        // Nothing has been read yet: the review is shown INSTEAD of the
        // Confirm sheet, not on top of a Confirm that already opened.
        XCTAssertFalse(app.textFields["manualFillUpLitersField"].exists,
                       "the review must precede the Confirm sheet, not follow it")
    }

    /// Hard rule 15: the manual door is a peer on this screen, side by side
    /// with Re-take and no harder to reach - and it opens the same manual form.
    func testTypeItIsAPeerOnTheReviewStep() {
        let app = launchCapture()
        shoot(app)

        let typeIt = app.buttons["captureReviewTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 15), "Type it must be on the review step")
        let retake = app.buttons["captureReviewRetakeButton"]
        XCTAssertTrue(retake.exists)
        // Peers: same row, same size. A consolation prize would be smaller or
        // pushed below the fold.
        XCTAssertEqual(typeIt.frame.height, retake.frame.height, accuracy: 1,
                       "Type it and Re-take must carry the same weight")
        XCTAssertEqual(typeIt.frame.minY, retake.frame.minY, accuracy: 1,
                       "Type it must sit beside Re-take, not below it")

        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "Type it must open the manual form")
    }

    // MARK: - Use this

    /// "Use this" runs the pipeline and lands exactly where the flow went
    /// before the review existed - the Confirm sheet with the scan's litres.
    /// The value proves the real pipeline ran on the accepted image.
    func testUseThisRunsThePipelineAndReachesConfirm() {
        let app = launchCapture()
        shoot(app)

        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15))
        useThis.tap()

        let liters = app.textFields["manualFillUpLitersField"]
        XCTAssertTrue(liters.waitForExistence(timeout: 20),
                      "Use this must reach the Confirm sheet")
        XCTAssertEqual((liters.value as? String) ?? "", "66.81",
                       "the accepted photo must be the one the pipeline read")
    }

    // MARK: - Re-take

    /// "Re-take" returns to the live capture surface with nothing kept, and -
    /// the assertion that matters - does NOT present Confirm. Existence of the
    /// button is not the behaviour; this is.
    func testRetakeReturnsToCaptureAndNeverPresentsConfirm() {
        let app = launchCapture()
        shoot(app)

        let retake = app.buttons["captureReviewRetakeButton"]
        XCTAssertTrue(retake.waitForExistence(timeout: 15))
        retake.tap()

        // Back on the live surface: the shutter is there and tappable again.
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10),
                      "Re-take must return to the live camera")
        XCTAssertTrue(shutter.isHittable, "the shutter must be usable again after a re-take")
        XCTAssertFalse(app.buttons["captureReviewUseButton"].exists,
                       "the review must be gone after a re-take")

        // The point of the test: nothing was accepted, so nothing was read.
        // A generous wait, because a wrongly-queued Confirm would arrive late.
        XCTAssertFalse(app.textFields["manualFillUpLitersField"]
                          .waitForExistence(timeout: 5),
                       "Re-take must not present the Confirm sheet")

        // And the surface still works: shooting again reviews again.
        shutter.tap()
        XCTAssertTrue(app.buttons["captureReviewUseButton"].waitForExistence(timeout: 15),
                      "a second shot must review again")
    }
}
