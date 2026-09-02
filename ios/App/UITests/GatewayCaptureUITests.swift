import XCTest

/// P6.3 - the gateway client on the Confirm sheet (docs/API.md -> "The device's
/// side of /extract"). The tests pin the two rules the feature exists for:
///
/// 1. The 3 s budget fires and the UI moves on, but the request is NOT
///    cancelled - the sheet stays usable and a late answer fills blanks only.
/// 2. The late answer is a suggestion, never an overwrite (hard rule 13), and
///    nothing arrives after save (F4). No paywall or upsell is reachable from
///    any capture flow (Pro is deferred; hard rule 7 + API.md).
///
/// The gateway is driven by `-seedGateway` (a deterministic scripted transport)
/// with `-seedGatewayDelay <seconds>` so the budget expiry and the late answer
/// land at known times. The seeded answer is distinctive (99.99 total, 1.679
/// price) so a late-answer fill is distinguishable from a derived value.
@MainActor
final class GatewayCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // No `-homeResetDatabase`: it makes Home reset the database on every
        // appearance, which wipes the seeded vehicle the moment the sheet
        // dismisses back to Home (the seeds themselves are idempotent).
        app.launchArguments = args
        app.launch()
        return app
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    private func openSheet(_ app: XCUIApplication) {
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "the Confirm sheet must be on screen")
    }

    /// Bring a number field clear of the keyboard and the pinned save bar and
    /// tap it (the same geometric helper the ConfirmManual suite uses - a tap
    /// on a covered field silently misses).
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

    private func timeoutMessage(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["gatewayTimeoutMessage"]
    }

    private func timeoutCopyText(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                             "Cloud reading continues in the background")).firstMatch
    }

    /// The exact copy (see also the localization gate test that pins EN and RU).
    private static let timeoutCopy = "Cloud reading continues in the background – keep going with what was read here."

    // MARK: - RV.8 the wait is visible from the first moment

    /// The bug this pins: production measured a 10.2 s cloud read, and the
    /// Confirm sheet showed NOTHING for the first 3 s of it and a motionless
    /// hourglass for the rest.
    ///
    /// `-seedGatewayBudget 25` widens the UI budget for this test only. Without
    /// it the `.running` state is unobservable: the budget starts when the sheet
    /// appears, and XCUITest's launch plus its first query routinely take longer
    /// than the product's 3 s, so the test would look for the in-flight banner
    /// after it had already been replaced - and would fail with the fix present.
    ///
    /// The assertion is on the RUNNING banner's own identifier and copy, never
    /// on "some banner exists": the timeout banner shares this flow, so a check
    /// against a shared identifier would pass with the bug fully in place.
    func testTheCloudReadIsVisibleWhileItRuns() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway",
                                "-seedGatewayDelay", "30", "-seedGatewayBudget", "25"])
        openSheet(app)

        let running = app.descendants(matching: .any)["gatewayReadingMessage"]
        XCTAssertTrue(running.waitForExistence(timeout: 10),
                      "the in-flight banner must be on screen while the request runs, not only at the budget")
        let copy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                                        "Reading this in the cloud")).firstMatch
        XCTAssertTrue(copy.exists, "the running banner must render its copy")

        // And the timeout banner is NOT up yet - which is what makes this a test
        // of the running state rather than of "a banner exists at some point".
        XCTAssertFalse(timeoutMessage(app).exists,
                       "the budget has not expired, so the timeout message must not be on screen")
    }

    /// The two states are one banner, not two: when the budget expires the
    /// running banner must be GONE, not stacked above the timeout one. Split
    /// from the test above so a failure names which half broke.
    func testTheRunningBannerGivesWayToTheBudgetMessage() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "30"])
        openSheet(app)

        XCTAssertTrue(timeoutMessage(app).waitForExistence(timeout: 10),
                      "the budget message must appear at the 3 s budget")
        XCTAssertFalse(app.descendants(matching: .any)["gatewayReadingMessage"].exists,
                       "the running banner must not remain beside the budget message")
    }

    // MARK: - The 3 s budget message (hard rule 7: it names its next step)

    func testGatewayTimeoutMessageNamesItsNextStep() {
        // Delay 30 s: the answer never arrives during the test, so the budget
        // expiry is the stable, assertable state.
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "30"])
        openSheet(app)

        // The on-device result (liters) is already on screen - the app never
        // waits on the gateway to show the card (F4).
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")

        // The budget expires and the message names the next step: carry on with
        // what was read locally. Assert the copy, not merely that "an element
        // exists".
        let message = timeoutMessage(app)
        XCTAssertTrue(message.waitForExistence(timeout: 8),
                      "the 3 s budget message must appear once the budget expires")
        let copy = timeoutCopyText(in: app)
        XCTAssertTrue(copy.exists, "the message text must be on screen")
        XCTAssertEqual(copy.label, Self.timeoutCopy,
                       "the message must render its documented copy")
    }

    // MARK: - The sheet stays usable throughout

    /// The user can type while the request is in flight, and a touched field
    /// survives the late answer (the "cannot overwrite a touched one" half of
    /// test 3 - a test that never touches a field first proves nothing).
    ///
    /// The answer is delayed 25 s (not 10 s) so the budget's 3 s fire and the
    /// answer's arrival are separated by a wide margin. The failure the tight
    /// delay caused: under a saturated machine the test's own typing (each
    /// keystroke waits on the app's main actor) takes longer than the 7 s
    /// between the 3 s budget and the 10 s answer, so the budget banner had
    /// already been replaced by the answer before the test looked for it. The
    /// widened delay makes that ordering immune to machine load without
    /// touching the 3 s product rule (`GatewayBudget.duration`).
    func testSheetStaysUsableAndTouchedFieldSurvivesTheLateAnswer() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "25"])
        openSheet(app)

        // Type into the total while the request is in flight (the answer lands
        // at 25 s, the budget fires at 3 s).
        focusField(app, "manualFillUpTotalField").typeText("88.88")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "88.88",
                       "the sheet must accept typing while the request is in flight")

        // The request was genuinely still in flight when the user typed: the
        // budget expires AFTER the typing, proving the two overlapped.
        XCTAssertTrue(timeoutMessage(app).waitForExistence(timeout: 8),
                      "the budget must expire after the user started typing")

        // The late answer arrives and fills the BLANK UNTOUCHED price field...
        // (the answer lands at 25 s, so the wait is a multiple of that, not the
        // old 8 s that raced the answer's arrival).
        let priceFilled = NSPredicate(format: "value == %@", "1.679")
        expectation(for: priceFilled, evaluatedWith: app.textFields["manualFillUpPricePerLField"])
        waitForExpectations(timeout: 25)

        // ...but it never overwrites the touched total (the gateway says 99.99).
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "88.88",
                       "a touched field is the user's own - no late answer may overwrite it")
    }

    // MARK: - A late answer fills blank untouched fields only

    func testLateAnswerFillsBlankUntouchedFields() {
        // Delay 15 s (not 6 s) - the same widening as the touched-field test.
        // The 6 s answer arrived only 3 s after the budget, so the test's own
        // blank-field assertions raced the answer's fill under a loaded machine
        // (openSheet + the assertions could outlast 6 s). The 12 s margin makes
        // the ordering immune to load without touching the 3 s product rule.
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "15"])
        openSheet(app)

        // Do NOT touch anything: total and price are blank and untouched.
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "")

        // The budget fires first...
        XCTAssertTrue(timeoutMessage(app).waitForExistence(timeout: 6))

        // ...then the late answer fills the blank fields (99.99 total, 1.679
        // price) and never refills the on-device-resolved liters (the gateway
        // says 55.00, the parser's 42.30 stands - F4). The wait spans the 15 s
        // answer, not the old 8 s that raced it.
        let totalFilled = NSPredicate(format: "value == %@", "99.99")
        expectation(for: totalFilled, evaluatedWith: app.textFields["manualFillUpTotalField"])
        waitForExpectations(timeout: 15)
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "1.679")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30",
                       "the on-device result has first claim - the gateway never fights it")
    }

    // MARK: - Nothing arrives after save (F4)

    func testNothingArrivesAfterSave() {
        // Delay 25 s: the save happens first, the answer lands after it. The
        // widened delay is the same class of fix as the touched-field test - a
        // 10 s answer raced the save under a loaded machine (typing could
        // outlast 10 s and let the answer fill before the save).
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "25"])
        openSheet(app)

        // Save with the on-device liters and a typed price; the total derives.
        focusField(app, "manualFillUpPricePerLField").typeText("1.679")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving must leave the Confirm sheet")

        // Wait past the point the gateway answer would have arrived.
        Thread.sleep(forTimeInterval: 26)

        // Re-open the saved entry (the newest row is first - LogStream orders
        // descending) and assert the gateway's distinctive 99.99 total is NOT
        // there: the derived 71.02 stands. Nothing arrives after save.
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved entry must be on Home")
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "71.02",
                       "the derived total must stand - a late answer after save is dropped (F4)")
    }

    // MARK: - No paywall or upsell reachable from any capture flow

    private func assertNoPaywall(_ app: XCUIApplication, context: String) {
        XCTAssertFalse(app.staticTexts["Tankbook Pro"].exists,
                       "\(context): the paywall title must not appear")
        XCTAssertFalse(app.navigationBars["Tankbook Pro"].exists,
                       "\(context): no paywall navigation must be reachable")
        let proAffordances = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pro"))
        XCTAssertEqual(proAffordances.count, 0,
                       "\(context): no Pro affordance may exist")
        let paywallIDs = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS %@", "paywall"))
        XCTAssertEqual(paywallIDs.count, 0,
                       "\(context): no paywall element may exist")
    }

    func testNoPaywallIsReachableFromTheCaptureSurfaceOrTheConfirmSheet() {
        // The capture cover and its two peer doors (Photos, Type it): none may
        // reach an upsell.
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "capture",
                                "-cameraStatus", "authorized"])
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10))
        assertNoPaywall(app, context: "capture cover")

        app.buttons["captureTypeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        assertNoPaywall(app, context: "Confirm sheet")
    }

    func testTimeoutBannerCarriesNoUpsellMidCapture() {
        // The exact surface this code runs on - the budget-expired state - must
        // carry no monetization (hard rule 7, and API.md forbids an upsell
        // mid-capture).
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "30"])
        openSheet(app)
        XCTAssertTrue(timeoutMessage(app).waitForExistence(timeout: 8))

        let copy = timeoutCopyText(in: app)
        let label = copy.exists ? copy.label : ""
        XCTAssertFalse(label.localizedCaseInsensitiveContains("Pro"), "the timeout copy must not upsell")
        XCTAssertFalse(label.localizedCaseInsensitiveContains("premium"), "the timeout copy must not upsell")
        XCTAssertFalse(label.localizedCaseInsensitiveContains("subscribe"), "the timeout copy must not upsell")
        assertNoPaywall(app, context: "timeout banner")
    }
}
