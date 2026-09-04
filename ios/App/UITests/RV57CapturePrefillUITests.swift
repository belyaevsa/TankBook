import XCTest

/// RV.57 - the capture-to-entry flow, driven end to end: shutter -> the RV.5
/// review -> "Use this" -> the entry view, pre-filled from a STUBBED local
/// parse (`FillUpScanTestSeed`), carrying the proceed note. The canned parse
/// substitutes ONLY the pipeline's output; the sheet hand-off and the form's
/// apply path are the exact shipped ones.
///
/// The two assertions that matter, and why they are not the vacuous ones:
///
/// - the FIELD VALUES are asserted (a pre-fill that lands nothing passes "the
///   view appeared");
/// - the late-answer test asserts the values are UNCHANGED while the editor is
///   open (not merely that nothing crashed), and THEN that the inbox gained the
///   item - the second is the actual RV.57 ruling.
@MainActor
final class RV57CapturePrefillUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A corpus receipt: the review step must show SOME photo before "Use this"
    /// (the canned recognition replaces OCR, never the review).
    private var fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RV57CapturePrefillUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")
            .appendingPathComponent("receipt-011-samara-diesel-ru.png")
            .path
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    private func captureFillUp(_ extraArgs: [String]) -> XCUIApplication {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture),
                      "the corpus fixture is missing: \(fixture)")
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedSettingsSignedIn", "-inboxReset",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-captureFixtureImage", fixture] + extraArgs
        app.launch()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
        return app
    }

    /// The real capture path: shutter -> review -> "Use this".
    private func shootAndUse(_ app: XCUIApplication) {
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "captureShutterButton never appeared")
        shutter.tap()
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the RV.5 review must appear after the shutter")
        useThis.tap()
    }

    /// Bring a number field clear of the keyboard and the pinned save bar, then
    /// tap it (the shared geometric helper - a tap on a covered field silently
    /// misses).
    @discardableResult
    private func focusField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
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

    // MARK: - L4: a capture pre-fills the entry, carries the note, and saves
    // WITHOUT the cloud ever answering

    /// The product thesis in one test: capture -> entry view opens AT ONCE,
    /// pre-filled from the local parse, with the dismissable note on screen, and
    /// Save reachable while the cloud never answers. Assert the field VALUES and
    /// a saved entry, never "the view appeared".
    func testCapturePrefillsTheEntryCarriesTheNoteAndSavesWithoutTheCloud() {
        let app = captureFillUp(["-seedFillUpScan", "-seedGateway", "-seedGatewayDelay", "30"])
        shootAndUse(app)

        // The entry view opens pre-filled from the LOCAL parse.
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 15),
                      "a capture must open the entry view, not leave the review")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "71.02",
                       "the local parse must pre-fill the total")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30",
                       "the local parse must pre-fill the liters")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "1.679",
                       "the local parse must pre-fill the price")

        // The note is present and dismissable...
        let note = app.descendants(matching: .any)["gatewayProceedNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 10),
                      "the proceed note must be on screen (the cloud reading is in flight)")
        XCTAssertTrue(app.buttons["gatewayProceedNoteDismissButton"].exists,
                      "the note must be dismissable")

        // ...and Save is reachable with the note on screen - it blocks nothing.
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled,
                      "Save must be reachable with the note on screen - the note blocks nothing")

        // Dismissing the note leaves Save alone, and the save writes the entry.
        app.buttons["gatewayProceedNoteDismissButton"].tap()
        XCTAssertFalse(note.exists, "dismissing must remove the note")
        XCTAssertTrue(save.isEnabled, "Save must stay reachable after dismissal")

        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving must leave capture and land on Home")
        XCTAssertTrue(app.buttons["logEntryButton"].firstMatch.waitForExistence(timeout: 5),
                      "the saved entry must be in the log")
    }

    // MARK: - L4: a late answer never touches the open editor, and reaches the inbox

    /// The RV.57 product-owner ruling pinned end to end: with a late answer
    /// injected WHILE the editor is open, the on-screen values do NOT change,
    /// and once the entry is saved the answer lands in the INBOX - never as a
    /// value that moved under the user's cursor.
    func testALateAnswerDoesNotTouchTheOpenEditorAndLandsInTheInbox() {
        let app = captureFillUp(["-seedFillUpScanSparse", "-seedGateway", "-seedGatewayDelay", "8"])
        shootAndUse(app)

        // The sparse local parse pre-filled only liters; total and price are blank.
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 15),
                      "a capture must open the entry view")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "")

        // The late answer arrives at 8 s. Wait past it.
        Thread.sleep(forTimeInterval: 9)

        // The on-screen values are UNCHANGED - the late answer (99.99 total,
        // 1.679 price) never filled the blanks. This is the assertion, not
        // merely that nothing crashed.
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30",
                       "the on-device liters must stand")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "",
                       "a late answer must NOT fill the blank total while the editor is open")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "",
                       "a late answer must NOT fill the blank price while the editor is open")

        // Save (type a total so two of three exist)...
        focusField(app, "manualFillUpTotalField").typeText("71.02")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "the save must be reachable after the late answer")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving must leave capture and land on Home")

        // ...and the late answer landed in the inbox, not in the entry.
        let bell = app.buttons["inboxBellButton"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "the inbox bell must be present")
        let counted = NSPredicate(format: "label == %@", "1 item in inbox")
        expectation(for: counted, evaluatedWith: bell)
        waitForExpectations(timeout: 20)
    }
}
