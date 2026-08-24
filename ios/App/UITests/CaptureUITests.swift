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
