import XCTest

/// P6.3 + RV.57 - the gateway client on the Confirm sheet (docs/API.md -> "The
/// device's side of /extract"). The tests pin the rules the feature exists for:
///
/// 1. The proceed note (RV.57) is visible while a request is in flight, is
///    dismissable, blocks nothing, and is ABSENT on a local-only parse.
/// 2. A LATE answer is a suggestion that goes to the INBOX, never a value that
///    moves under the user's cursor (the RV.57 product-owner ruling): the
///    on-screen values do NOT change while the editor is open.
/// 3. Nothing arrives in the entry after save - the entry is corrected by its
///    owner alone (F4). No paywall or upsell is reachable from any capture flow.
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

    private func note(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["gatewayProceedNote"]
    }

    private func noteCopyText(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                             "A more reliable reading may still arrive")).firstMatch
    }

    /// The exact copy (see also the localization gate test that pins EN and RU).
    private static let proceedNoteCopy = "A more reliable reading may still arrive. You can proceed now."

    // MARK: - RV.57 the proceed note (no spinner, dismissable, blocks nothing)

    /// The note is visible while the request is in flight - the RV.8 "the wait
    /// must be visible" invariant, re-framed: it says "proceed now" rather than
    /// "keep typing", and it carries no spinner (the whole point is that the
    /// user need not wait).
    func testTheProceedNoteIsVisibleWhileTheRequestIsInFlight() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway",
                                "-seedGatewayDelay", "30"])
        openSheet(app)

        XCTAssertTrue(note(app).waitForExistence(timeout: 10),
                      "the proceed note must be on screen while the request runs")
        XCTAssertTrue(noteCopyText(in: app).exists,
                      "the note must render its copy")
        XCTAssertTrue(app.buttons["gatewayProceedNoteDismissButton"].exists,
                      "the note must be dismissable, never an unremovable nag")
    }

    /// The note's presence is derived from there being an in-flight request -
    /// absent on a local-only parse (no `-seedGateway`, so no transport is armed
    /// and the phase never leaves `.idle`).
    func testTheProceedNoteIsAbsentOnALocalOnlyParse() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse"])
        openSheet(app)

        XCTAssertFalse(note(app).exists,
                       "a local-only parse has no in-flight request, so the note must be absent")
        XCTAssertFalse(app.buttons["gatewayProceedNoteDismissButton"].exists,
                       "no note, no dismiss affordance")
    }

    /// The × dismisses the note, and Save stays reachable with the note on
    /// screen (hard rule 7: the note blocks nothing, not even by covering the
    /// save bar). The assert-on-save-enabled-before-dismiss is the vacuous trap
    /// named in the brief: asserting the string exists says nothing about
    /// whether it blocks the save.
    func testTheProceedNoteIsDismissableAndDoesNotBlockSaving() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillLocked", "-seedGateway",
                                "-seedGatewayDelay", "30"])
        openSheet(app)

        XCTAssertTrue(note(app).waitForExistence(timeout: 10),
                      "precondition: the note is on screen")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled,
                      "Save must be reachable with the note on screen - the note blocks nothing")

        app.buttons["gatewayProceedNoteDismissButton"].tap()
        XCTAssertFalse(note(app).exists,
                       "dismissing the note must remove it from the sheet")
        XCTAssertTrue(save.isEnabled,
                      "Save must stay reachable after the note is dismissed")
    }

    /// The note names its next step (proceed now) - assert the copy, not merely
    /// that "an element exists".
    func testTheProceedNoteNamesItsNextStep() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway",
                                "-seedGatewayDelay", "30"])
        openSheet(app)

        XCTAssertTrue(note(app).waitForExistence(timeout: 10),
                      "the note must appear once the request is in flight")
        let copy = noteCopyText(in: app)
        XCTAssertTrue(copy.exists, "the note text must be on screen")
        XCTAssertEqual(copy.label, Self.proceedNoteCopy,
                       "the note must render its documented copy")
    }

    // MARK: - RV.57 the late answer never touches the open editor

    /// The load-bearing assertion (the product-owner ruling): a late answer that
    /// arrives WHILE the editor is open leaves the on-screen values UNCHANGED -
    /// not merely "nothing crashed". Under the pre-RV.57 behaviour the late
    /// answer filled the blank total (99.99) and price (1.679); now it must not.
    func testTheLateAnswerDoesNotChangeTheOpenEditor() {
        // Delay 15 s (not 6 s) so the budget's 3 s fire and the answer's arrival
        // are separated by a wide margin, immune to machine load.
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway",
                                "-seedGatewayDelay", "15"])
        openSheet(app)

        // The on-device result (liters) is on screen; total and price are blank.
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "")

        // Wait past the answer's arrival (15 s).
        Thread.sleep(forTimeInterval: 16)

        // The values are UNCHANGED - the late answer (99.99 total, 1.679 price)
        // never moved under the user's cursor. It is held for the inbox instead.
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30",
                       "the on-device liters must stand")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "",
                       "a late answer must NOT fill the blank total while the editor is open")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "",
                       "a late answer must NOT fill the blank price while the editor is open")
    }

    // MARK: - Nothing arrives in the entry after save (F4, amended RV.38)

    func testNothingArrivesInTheEntryAfterSave() {
        // Delay 25 s: the save happens first, the answer lands after it.
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

        // Re-open the saved entry and assert the gateway's distinctive 99.99
        // total is NOT there: the derived 71.02 stands. The late answer went to
        // the inbox (RV.57/RV.38), never into the entry.
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved entry must be on Home")
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "71.02",
                       "the derived total must stand - a late answer lands in the inbox, never the entry")
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
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "capture",
                                "-cameraStatus", "authorized"])
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10))
        assertNoPaywall(app, context: "capture cover")

        app.buttons["captureTypeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        assertNoPaywall(app, context: "Confirm sheet")
    }

    func testTheProceedNoteCarriesNoUpsellMidCapture() {
        let app = launch(args: ["-seedVehicleForUITests", "-presentScreen", "confirmManual",
                                "-seedConfirmPrefillSparse", "-seedGateway", "-seedGatewayDelay", "30"])
        openSheet(app)
        XCTAssertTrue(note(app).waitForExistence(timeout: 10))

        let copy = noteCopyText(in: app)
        let label = copy.exists ? copy.label : ""
        // "proceed" contains "pro", so a bare "Pro" substring check would flag
        // the note's own copy - assert the actual upsell words instead.
        XCTAssertFalse(label.localizedCaseInsensitiveContains("premium"), "the note must not upsell")
        XCTAssertFalse(label.localizedCaseInsensitiveContains("subscribe"), "the note must not upsell")
        XCTAssertFalse(label.localizedCaseInsensitiveContains("upgrade"), "the note must not upsell")
        assertNoPaywall(app, context: "proceed note")
    }
}
