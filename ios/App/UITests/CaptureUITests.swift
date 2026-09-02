import XCTest

/// P2.1 Capture camera screen tests: the F8 denied-permission fallback (manual
/// form + card + the three next steps), the "Type it" path with permission
/// granted, the four-mode row, the X closing the cover, and denied never being
/// a dead end (hard rule 7). Camera status is forced with `-cameraStatus`.
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

    /// The flag-off pump path is the ordinary manual door: no pre-fill, no
    /// failure message (hard rule 15) - the feature is simply not offered.
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
        // Each field is scrolled clear before it is tapped: the numbers card
        // sits below Date/Odometer/Fuel, so the keyboard raised by TOTAL can
        // cover LITERS, and a covered tap misses silently (typeText then fails
        // with a focus error that reads like a broken field).
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
    /// (`CaptureMode.modes(for:)`), never a fixed set of four.
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

        let service = app.buttons["captureMode_service"]
        XCTAssertTrue(service.waitForExistence(timeout: 5), "captureMode_service never appeared")
        service.tap()
        XCTAssertTrue(service.isSelected)
        XCTAssertFalse(app.buttons["captureMode_fillUpAuto"].isSelected)
    }

    /// An EV's mirror image, plus the PJ.12 dead chip: EV charging is v1.x, so
    /// no Charge chip is offered and the EV opens on Service - a working mode.
    func testAnEVShowsNoChargeAndOpensOnService() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-powertrain", "ev"])
        openCapture(app)

        XCTAssertFalse(app.buttons["captureMode_charge"].exists,
                       "PJ.12: an EV must not be offered the dead Charge chip")
        XCTAssertFalse(app.buttons["captureMode_fillUpAuto"].exists,
                       "an EV must not be offered Fill-up")
        XCTAssertTrue(app.buttons["captureMode_service"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["captureMode_expense"].exists)
        XCTAssertTrue(app.buttons["captureMode_service"].isSelected,
                      "an EV must open on Service - a mode that works - not on a dead chip")
    }

    /// The plug-in hybrid keeps the Fill-up door but loses Charge with
    /// everyone else until EV charging is v1.x (PJ.12).
    func testAPlugInHybridKeepsFillUpAndLosesCharge() {
        let app = launch(args: ["-homeResetDatabase",
                                "-presentScreen", "capture", "-cameraStatus", "authorized",
                                "-powertrain", "phev"])
        openCapture(app)

        XCTAssertTrue(app.buttons["captureMode_fillUpAuto"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["captureMode_charge"].exists,
                       "PJ.12: a plug-in hybrid must not be offered the dead Charge chip")
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

        let trends = app.buttons["tabbar.trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10), "tabbar.trends never appeared")
        trends.tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))

        let button = app.buttons["captureButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10))

        // Not a tab: opening capture must not move the selection.
        XCTAssertTrue(app.buttons["tabbar.trends"].isSelected,
                      "capture is not a tab - selection must stay on Trends")

        // Closing the cover returns to wherever it was opened from.
        let close = app.buttons["captureCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "captureCloseButton never appeared")
        close.tap()
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

        let trends = app.buttons["tabbar.trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10), "tabbar.trends never appeared")
        trends.tap()
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
        // hold is that the sheet itself does not carry it. SwiftUI pages expose
        // their sheet as `app.sheets`; the fallback is non-hittability.
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

/// PJ.6 tests live in an extension (not the class body) so the class stays
/// under SwiftLint's `type_body_length` while `-only-testing:` still picks
/// them up. Each mode asserts the identifier of the sheet that opens, never
/// that "a sheet appeared"; the mode -> form mapping is pinned at L1.
@MainActor
extension CaptureUITests {

    /// PJ.6 launch helper: the capture cover with a seeded car, camera status
    /// authorized by default. `-seedVehicleForUITests` seeds when a Manual or
    /// Service form loads; the Expense test passes `-seedHomeEmptyVehicle`.
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
        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 5), "captureTypeItButton never appeared")
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "Fill-up Type it must open the fill-up form, by identifier")
    }

    func testTypeItInServiceModeOpensTheServiceForm() {
        let app = captureApp()
        let service = app.buttons["captureMode_service"]
        XCTAssertTrue(service.waitForExistence(timeout: 5), "captureMode_service never appeared")
        service.tap()
        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 5), "captureTypeItButton never appeared")
        typeIt.tap()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10),
                      "Service Type it must open the service entry form, by identifier")
        XCTAssertFalse(app.textFields["manualFillUpTotalField"].exists,
                       "Service Type it must not open the fill-up form")
    }

    func testTypeItInExpenseModeOpensTheExpenseForm() {
        let app = captureApp(seed: "-seedHomeEmptyVehicle")
        let expense = app.buttons["captureMode_expense"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5), "captureMode_expense never appeared")
        expense.tap()
        let typeIt = app.buttons["captureTypeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 5), "captureTypeItButton never appeared")
        typeIt.tap()
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

// MARK: - PJ.12b: the caption reads true per powertrain and per gate

/// The capture caption (CaptureView.captureCaption) must read true for each
/// powertrain and gate state - the vacuous trap is asserting "a caption
/// renders", which it always does. These assert WHICH sentence renders.
@MainActor
extension CaptureUITests {
    func testICECaptionDoesNotClaimPumpWhileTheGateFails() {
        let app = captureApp("authorized", ["-powertrain", "ice"])
        XCTAssertTrue(app.staticTexts["Receipts are detected automatically"].waitForExistence(timeout: 5),
                      "ICE must read 'Receipts are detected automatically' while the gate fails")
        XCTAssertFalse(app.staticTexts["Receipts and pump displays are detected automatically"].exists,
                       "the pump claim must not render while the gate fails")
    }

    func testEVCaptionNeverClaimsPumpDetection() {
        let app = captureApp("authorized", ["-powertrain", "ev"])
        XCTAssertTrue(app.staticTexts["Receipts are detected automatically"].waitForExistence(timeout: 5),
                      "an EV must read 'Receipts are detected automatically'")
        XCTAssertFalse(app.staticTexts["Receipts and pump displays are detected automatically"].exists,
                       "an EV has no pump display - the claim must never reach it")
    }
}
