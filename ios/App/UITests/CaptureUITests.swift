import XCTest

/// P2.1 Capture camera screen tests. The five behaviours that carry the task:
/// the F8 denied-permission fallback (manual form + permission card + all
/// three next steps), the "Type it" path to the manual form with permission
/// granted, the four-mode row with Fill-up default and live selection, the X
/// closing the cover, and the denied state never being a dead end (a savable
/// manual form - hard rule 7).
///
/// The camera status is forced per test with `-cameraStatus
/// denied|authorized` so nothing depends on the simulator's (absent) camera.
@MainActor
final class CaptureUITests: XCTestCase {

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

    // MARK: - F8: denied permission


    /// Scroll a number field clear of the keyboard and the pinned save bar, then
    /// tap it. `app.scrollViews.firstMatch` is the screen BEHIND a presented
    /// sheet, so the drag must target the hittable one, anchored above the bar -
    /// a swipe starting lower is eaten by the keyboard.
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

    func testDeniedShowsManualFormWithCardAndAllThreeNextSteps() {
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "denied"])
        openCapture(app)

        // Assert the card's copy, not just its existence.
        let card = app.staticTexts["Scanning needs the camera – enable in Settings."]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "the F8 permission card must render its documented copy")
        XCTAssertTrue(app.staticTexts["capturePermissionCard"].exists
                      || app.otherElements["capturePermissionCard"].exists,
                      "the permission card element must exist")

        // The manual form is open beneath the card.
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].exists,
                      "the denied state must show the manual form")

        // All three next steps are present and tappable.
        for identifier in ["capturePermissionSettingsButton",
                           "capturePermissionTypeItButton",
                           "capturePermissionPhotosButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) must exist")
            XCTAssertTrue(button.isHittable, "\(identifier) must be tappable")
        }
    }

    func testDeniedStateCanStillSaveFromEmbeddedManualForm() {
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "denied"])
        openCapture(app)
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10))

        // Type any two of the three - save enables live (the ConfirmManual rule).
        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("71.02")
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("42.30")

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "the denied state must allow saving")
        save.tap()

        // Saving dismisses the cover straight back to the opener: denied is
        // not a dead end (docs/ERRORS.md F8, hard rule 7).
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving from the denied state must leave capture")
    }

    // MARK: - "Type it" path with permission granted

    func testTypeItOpensManualFormWhenGranted() {
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized"])
        openCapture(app)

        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10))
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5),
                      "Type it must present the manual form")
    }

    // MARK: - P2.7 pump photo, flag off

    /// The pump path with the flag off is the ordinary manual door, pre-filled
    /// with nothing and with no message implying failure (hard rule 15): the
    /// feature is simply not offered, so there is no error to show. Asserting
    /// the ordinary empty form - blank fields, the standard save hint - is the
    /// proof that no error state was injected in its place.
    func testPumpCaptureWithFlagOffOpensEmptyManualFormAndSavesWithNoError() {
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-seedPumpCapture"])
        openCapture(app)

        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10))
        typeIt.tap()

        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        // Pre-filled with nothing: a flag-off pump capture injects no value and
        // no error - the form is the ordinary empty one.
        XCTAssertTrue((total.value as? String)?.isEmpty ?? true,
                      "flag-off pump capture must pre-fill nothing")
        XCTAssertNotEqual(total.value as? String ?? "", "0")

        // The standard empty-form hint is the only guidance shown, so the pump
        // path carries no "not supported" / failure message.
        XCTAssertTrue(app.staticTexts["Enter total and liters to save"].exists,
                      "the ordinary empty-form hint must be the only guidance")

        // Savable, so it is never a dead end.
        //
        // Each field is scrolled clear before it is tapped: since the
        // 2026-08-25 field reorder (docs/DESIGN.md - entry form order) the
        // three-number card sits below Date, Odometer, Station and Fuel, so the
        // keyboard raised by TOTAL can cover LITERS. A tap on a covered field
        // silently misses and `typeText` fails with "Neither element nor any
        // descendant has keyboard focus", which reads like a broken field.
        focusNumberField(app, "manualFillUpTotalField").typeText("71.02")
        focusNumberField(app, "manualFillUpLitersField").typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving from the pump path must leave capture")
    }

    // MARK: - Mode row

    /// The mode row is a function of the selected car's powertrain
    /// (`CaptureMode.modes(for:)`), not a fixed set of four: a petrol car can
    /// never log a charging session, so offering the chip invites an entry the
    /// vehicle cannot have.
    func testModeRowOffersOnlyWhatThePowertrainCanLog() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-powertrain", "ice"])
        openCapture(app)

        // Assert labels, not just identifiers: a mode whose label is wrong must fail.
        let offered: [(String, String)] = [
            ("captureMode_fillUpAuto", "Fill-up · auto"),
            ("captureMode_service", "Service"),
            ("captureMode_expense", "Expense")
        ]
        for (identifier, label) in offered {
            let chip = app.buttons[identifier]
            XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(identifier) must exist")
            XCTAssertEqual(chip.label, label, "\(identifier) must carry its localized label")
        }

        XCTAssertFalse(app.buttons["captureMode_charge"].exists,
                       "a petrol car must not be offered Charge")

        XCTAssertTrue(app.buttons["captureMode_fillUpAuto"].isSelected,
                      "Fill-up must be selected by default on a petrol car")

        app.buttons["captureMode_service"].tap()
        XCTAssertTrue(app.buttons["captureMode_service"].isSelected)
        XCTAssertFalse(app.buttons["captureMode_fillUpAuto"].isSelected)
    }

    /// An EV is the mirror image, and it must not open on a mode it cannot use.
    func testAnEVIsOfferedChargeAndNeverFillUp() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-powertrain", "ev"])
        openCapture(app)

        let charge = app.buttons["captureMode_charge"]
        XCTAssertTrue(charge.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["captureMode_fillUpAuto"].exists,
                       "an EV must not be offered Fill-up")
        XCTAssertTrue(charge.isSelected, "an EV must open on Charge, not on a mode it lacks")
    }

    /// The four-chip case. A plain hybrid has no plug, so only a plug-in gets
    /// both - and this is the layout that has to survive Russian without
    /// wrapping a chip onto its own row.
    func testOnlyAPlugInHybridIsOfferedBothFillUpAndCharge() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-powertrain", "phev"])
        openCapture(app)

        XCTAssertTrue(app.buttons["captureMode_fillUpAuto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["captureMode_charge"].exists,
                      "a plug-in hybrid must be offered Charge")
        XCTAssertTrue(app.buttons["captureMode_service"].exists)
        XCTAssertTrue(app.buttons["captureMode_expense"].exists)
    }

    func testAPlainHybridIsNotOfferedCharge() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-powertrain", "hybrid"])
        openCapture(app)

        XCTAssertTrue(app.buttons["captureMode_fillUpAuto"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["captureMode_charge"].exists,
                       "a plain hybrid has no plug - its battery charges from the engine")
    }

    // MARK: - X closes the cover

    func testXClosesCoverAndReturnsToOpener() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized"])
        openCapture(app)

        let close = app.buttons["captureCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "the cover must close back to the opener")
    }

    // MARK: - P2.1b: wired into the app (no launch argument)

    /// The whole point of P2.1b: a real user - a plain launch, no
    /// `-presentScreen` - can reach Capture by tapping the tab bar's centre
    /// button. This is the only test in the suite that proves the screen is not
    /// dead code in Release, because the previous bug was that `ModalRoute
    /// .capture` was set only by the `#if DEBUG` hook.
    func testCenterButtonReachesCaptureWithoutLaunchArgument() {
        let app = launch(args: ["-homeResetDatabase", "-seedHomeFullHistory",
                                "-cameraStatus", "authorized"])

        let button = app.buttons["captureButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10),
                      "the centre capture button must exist on the tab bar")
        button.tap()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "tapping the centre button must present the Capture cover")
        XCTAssertTrue(app.buttons["captureMode_fillUpAuto"].waitForExistence(timeout: 5),
                      "the real Capture screen must be on screen, not an empty shell")
    }

    /// The centre button is NOT a tab: tapping it leaves the selection where it
    /// was, and closing the cover returns to the originating tab with that
    /// tab's navigation stack intact (docs/SCREENMAP.md: "X closes back to
    /// wherever it was opened from").
    func testCenterButtonIsNotATabAndDismissReturnsToOriginatingTab() {
        let app = launch(args: ["-homeResetDatabase", "-seedHomeFullHistory",
                                "-cameraStatus", "authorized"])

        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))

        let button = app.buttons["captureButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10))

        // Not a tab: opening capture must not move the selection.
        XCTAssertTrue(app.buttons["tabbar.trends"].isSelected,
                      "capture is not a tab - selection must stay on Trends")

        // Closing the cover returns to wherever it was opened from.
        app.buttons["captureCloseButton"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5),
                      "closing capture must return to the originating tab")
        XCTAssertTrue(app.buttons["tabbar.trends"].isSelected,
                      "the originating tab must still be selected")
    }

    /// Capture is not a destination and must not disturb the tab's own
    /// navigation stack: open it from Trends with a screen already pushed, and
    /// dismissing must leave that pushed screen on Trends' stack (this is what
    /// keeping `TabView` as the state engine buys).
    func testCaptureFromTrendsPreservesThePushedScreen() {
        let app = launch(args: ["-homeResetDatabase", "-seedHomeDuplicate",
                                "-cameraStatus", "authorized"])

        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))

        // Push a screen on Trends' own stack via the excluded-entries footnote
        // (the duplicate seed produces one excluded entry, which Trends links).
        let footnote = app.buttons["trendsExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 5),
                      "the excluded-entries footnote must link to Edit entry on Trends")
        footnote.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5),
                      "Trends must have a pushed screen before capture opens")

        // Open capture from Trends.
        let capture = app.buttons["captureButton"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        capture.tap()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tabbar.trends"].isSelected,
                      "capture is not a destination - Trends stays selected")

        // Dismiss: the pushed screen is still on Trends' stack.
        app.buttons["captureCloseButton"].tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5),
                      "capture must not disturb the tab's navigation stack")
    }

    /// Hard rule 15 asserted: manual entry and capture are peer paths of equal
    /// standing, both one tap from Home - neither reachable only via the other.
    func testBothDoorsSideBySideFromHome() {
        let app = launch(args: ["-homeResetDatabase", "-seedHomeFullHistory",
                                "-cameraStatus", "authorized"])

        // Door one: the centre button opens Capture.
        let capture = app.buttons["captureButton"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        capture.tap()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10))
        app.buttons["captureCloseButton"].tap()

        // Door two: "Type it" opens the manual form, without any scan first.
        let typeIt = app.buttons["typeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 5))
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5),
                      "Type it must present the manual form - the second door")
    }

    // MARK: - PJ.1: the capture pipeline (shutter + Photos -> Confirm prefill)

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test can read a fixture image by its host
    /// path - passed through `-captureFixtureImage` - and OCR it for real.
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

    /// The shutter takes a real frame (here the injected fixture, since the
    /// simulator has no camera) and opens the Confirm sheet with the litres the
    /// scan resolved, pre-filled and dimmed. NO `-seedConfirmPrefill` argument -
    /// the value must come from the real pipeline, or this test proves nothing.
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

        let liters = app.textFields["manualFillUpLitersField"]
        XCTAssertTrue(liters.waitForExistence(timeout: 15),
                      "the shutter must open the Confirm sheet")
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

    /// The Photos door feeds the SAME path as the shutter: pick an image (here
    /// the injected fixture, since the out-of-process picker cannot be driven)
    /// and the identical Confirm sheet opens.
    func testPhotosDoorFeedsTheSamePipeline() {
        let fixture = fixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-captureFixtureImage", fixture])
        openCapture(app)

        let photos = app.buttons["capturePhotosButton"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        photos.tap()

        let liters = app.textFields["manualFillUpLitersField"]
        XCTAssertTrue(liters.waitForExistence(timeout: 15),
                      "the Photos door must open the Confirm sheet")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "66.81",
                       "the Photos pick must pre-fill the same litres as the shutter")
    }

    /// Hard rule 15: a scan that resolves nothing opens the ordinary empty
    /// manual form, never an error and never a dead end. receipt-034 is the
    /// contract-zero-price fixture the parser resolves nothing from.
    func testAResolvedNothingScanOpensTheEmptyFormNotAnError() {
        let fixture = fixturesRoot + "/receipts/receipt-034-lukoil-m11-ekto95-contract-zero-price-ru.jpeg"
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-captureFixtureImage", fixture])
        openCapture(app)

        app.buttons["captureShutterButton"].tap()

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

    // MARK: - P6.10: the alpha-testing notice on the capture surface

    /// The exact copy, so the assertions check what the user reads, not just
    /// that "some element exists". The full sentence is too long for a query
    /// string (XCTest's 128-char limit), so the lookup matches the label by
    /// predicate and the copy is still asserted verbatim via `label`. The `+`
    /// join keeps each line under the lint limit; the UI tests are outside the
    /// localization gate's source scan, and this constant never reaches a
    /// `Text` initialiser.
    private static let alphaNoticeCopy = "Recognition is in alpha testing – it can't get every field right yet. "
        + "Your captures improve it, so keep them coming and bear with mistakes."

    private func alphaNotice(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["captureAlphaNotice"]
    }

    private func alphaNoticeCopyText(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                             "Recognition is in alpha testing")).firstMatch
    }

    /// The notice is on the capture surface (a disclosure, `inkSoft`, never
    /// amber) before the shutter - it renders on the live camera surface with
    /// no captures yet, and carries its dismiss affordance.
    func testAlphaNoticeRendersOnCaptureSurface() {
        let app = launch(args: ["-homeResetDatabase", "-presentScreen", "capture",
                                "-cameraStatus", "authorized", "-alphaNoticeReset"])
        openCapture(app)

        let copy = alphaNoticeCopyText(in: app)
        XCTAssertTrue(copy.waitForExistence(timeout: 5),
                      "the alpha notice must render on the capture surface")
        XCTAssertEqual(copy.label, Self.alphaNoticeCopy,
                       "the notice must render its exact copy")
        XCTAssertTrue(alphaNotice(app).exists,
                      "the notice container must be present on the capture surface")
        XCTAssertTrue(app.buttons["captureAlphaNoticeDismissButton"].exists,
                      "the notice must be dismissable, never an unremovable nag")
    }

    /// The half that keeps it from becoming a nag: the notice is NEVER on the
    /// Confirm sheet. It lives only on the capture surface, so a Confirm sheet
    /// (here the manual form, opened via the peer "Type it" door) must not
    /// carry it. On the sheet it is neither present nor hittable.
    func testAlphaNoticeNeverOnConfirmSheet() {
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests",
                                "-presentScreen", "capture",
                                "-cameraStatus", "authorized", "-alphaNoticeReset"])
        openCapture(app)
        XCTAssertTrue(alphaNoticeCopyText(in: app).waitForExistence(timeout: 5),
                      "precondition: the notice is on the capture surface")

        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 5))
        typeIt.tap()

        let confirm = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "the Confirm sheet must be on screen")

        // The notice is structurally part of the capture surface, which stays
        // mounted beneath the sheet - so `exists` is not the guard. What must
        // hold is that the sheet itself does not carry it: the notice must be
        // absent from the sheet's own hierarchy and unreachable in the
        // foreground. SwiftUI pages expose their sheet as `app.sheets`; if that
        // lookup is unavailable the fallback is non-hittability of the copy.
        let sheetCount = app.sheets.count
        if sheetCount > 0 {
            let sheet = app.sheets.firstMatch
            XCTAssertFalse(sheet.descendants(matching: .any)["captureAlphaNotice"].exists,
                           "the alpha notice must not exist inside the Confirm sheet")
            XCTAssertFalse(sheet.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@",
                                      "Recognition is in alpha testing")).firstMatch.exists,
                "the alpha notice copy must not exist inside the Confirm sheet")
        }
        XCTAssertFalse(alphaNoticeCopyText(in: app).isHittable,
                       "the notice must not be visible or reachable on the Confirm sheet")
        XCTAssertFalse(app.buttons["captureAlphaNoticeDismissButton"].isHittable,
                       "the notice's dismiss affordance must not be reachable on the Confirm sheet")
    }

    /// Dismissal persists across launches (test 2 of the task): the × hides the
    /// notice for the day, and a relaunch the same day must not bring it back.
    /// The relaunch deliberately drops `-alphaNoticeReset` - the point is that
    /// the persisted dismissal, not a launch argument, is what keeps it hidden.
    func testAlphaNoticeDismissalPersistsAcrossLaunches() {
        let app = launch(args: ["-homeResetDatabase", "-presentScreen", "capture",
                                "-cameraStatus", "authorized", "-alphaNoticeReset"])
        openCapture(app)
        XCTAssertTrue(alphaNoticeCopyText(in: app).waitForExistence(timeout: 5))

        app.buttons["captureAlphaNoticeDismissButton"].tap()
        XCTAssertFalse(alphaNotice(app).exists,
                       "dismissing must remove the notice from the capture surface")

        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-homeResetDatabase", "-presentScreen", "capture",
                                    "-cameraStatus", "authorized"]
        relaunch.launch()
        XCTAssertTrue(relaunch.buttons["captureCloseButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(alphaNotice(relaunch).exists,
                       "a dismissal must persist across launches (same day)")
    }

    /// Retirement by experience: once the device has logged three captures the
    /// user judges recognition from their own scans, and the disclosure has
    /// done its job. Full history is well past the threshold, so the notice is
    /// gone even though it was never dismissed - never a permanent nag.
    func testAlphaNoticeRetiresAfterThreeCaptures() {
        let app = launch(args: ["-homeResetDatabase", "-seedHomeFullHistory",
                                "-presentScreen", "capture",
                                "-cameraStatus", "authorized", "-alphaNoticeReset"])
        openCapture(app)

        XCTAssertFalse(alphaNotice(app).exists,
                       "after three captures the notice must retire permanently")
        XCTAssertFalse(app.buttons["captureAlphaNoticeDismissButton"].exists,
                       "a retired notice must carry no dismiss affordance either")
    }

    /// Retirement by repetition: three dismissals across three days means the
    /// user has read the notice three times; further repetition is nagging. The
    /// seeded dismissal count stands in for the three separate days.
    func testAlphaNoticeRetiresAfterThreeDismissals() {
        let app = launch(args: ["-homeResetDatabase", "-presentScreen", "capture",
                                "-cameraStatus", "authorized",
                                "-alphaNoticeDismissCount", "3"])
        openCapture(app)

        XCTAssertFalse(alphaNotice(app).exists,
                       "after three dismissals the notice must retire permanently")
    }
}

// MARK: - PJ.6: "Type it" opens the form for the selected mode

/// The PJ.6 tests live in an extension of `CaptureUITests` (not inside the
/// class body) so the class stays under SwiftLint's `type_body_length` floor
/// while `-only-testing:TankbookUITests/CaptureUITests` still picks them up.
///
/// The shape of the assertion matters: each mode asserts the identifier of the
/// sheet that opens, never that "a sheet appeared" (the P6.20 shape). A
/// mutation that sends every mode to the fill-up form fails Service and
/// Expense; one that only breaks the permission card's "Type it" fails the
/// denied test. The mode -> form mapping itself is pinned at L1 in
/// `CaptureModeTests.manualEntryFormIsPinnedForEveryMode`.
@MainActor
extension CaptureUITests {

    /// PJ.6 launch helper: the capture cover with a seeded car. The camera
    /// status defaults to authorized; the denied test overrides it, and
    /// `-captureMode` pins the mode where the denied layout has no mode row.
    ///
    /// `-seedVehicleForUITests` seeds when a Manual fill-up or Service entry
    /// form loads; the Expense entry alone never triggers it (it only ever ran
    /// nested inside a Service entry, which seeded first), so the expense test
    /// passes `-seedHomeEmptyVehicle`, which Home's own task seeds.
    private func captureApp(_ status: String = "authorized",
                            _ extraArgs: [String] = [],
                            seed: String = "-seedVehicleForUITests") -> XCUIApplication {
        let app = launch(args: ["-homeResetDatabase", seed,
                                "-presentScreen", "capture", "-cameraStatus", status]
                            + extraArgs)
        openCapture(app)
        return app
    }

    /// Fill-up is the default mode; no chip tap needed. The sheet that opens is
    /// asserted by identifier, never that "a sheet appeared".
    func testTypeItInFillUpModeOpensTheFillUpForm() {
        let app = captureApp()
        app.buttons["captureTypeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "Fill-up Type it must open the fill-up form, by identifier")
    }

    func testTypeItInServiceModeOpensTheServiceForm() {
        let app = captureApp()
        app.buttons["captureMode_service"].tap()
        app.buttons["captureTypeItButton"].tap()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10),
                      "Service Type it must open the service entry form, by identifier")
        XCTAssertFalse(app.textFields["manualFillUpTotalField"].exists,
                       "Service Type it must not open the fill-up form")
    }

    func testTypeItInExpenseModeOpensTheExpenseForm() {
        let app = captureApp(seed: "-seedHomeEmptyVehicle")
        app.buttons["captureMode_expense"].tap()
        app.buttons["captureTypeItButton"].tap()
        XCTAssertTrue(app.textFields["expenseEntryTitleField"].waitForExistence(timeout: 10),
                      "Expense Type it must open the expense entry form, by identifier")
        XCTAssertFalse(app.textFields["manualFillUpTotalField"].exists,
                       "Expense Type it must not open the fill-up form")
    }

    /// The F8 escape obeys the mode too (the brief's second call site): the
    /// permission card's "Type it" is the door a user reaches when the camera
    /// is refused, and sending them to the wrong form is worse, not better.
    /// The mode is forced with `-captureMode service` because the denied
    /// layout has no mode row to tap - exactly the state a real denied user is
    /// in, with the default mode overridden by the debug hook the test drives.
    func testDeniedPermissionTypeItOpensTheFormForTheSelectedMode() {
        let app = captureApp("denied", ["-captureMode", "service"])
        let typeIt = app.buttons["capturePermissionTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10))
        typeIt.tap()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10),
                      "the permission card's Type it must open the form for the selected mode")
    }
}
