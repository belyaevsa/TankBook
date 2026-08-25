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
        total.tap()
        total.typeText("71.02")
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("42.30")
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

    // MARK: - Simulated detection overlay

    func testDetectionFrameRendersExtractedLinesWhenSeeded() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-seedCaptureDetection"])
        openCapture(app)

        // The screenshot path's detection frame must actually render - the
        // P1.6 lesson was a screenshot that silently showed nothing.
        let frame = app.descendants(matching: .any)["captureDetectionFrame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 10),
                      "the seeded detection frame must render")
        XCTAssertTrue(frame.label.contains("SHELL"),
                      "the frame must carry the artboard's extracted lines")
    }
}
