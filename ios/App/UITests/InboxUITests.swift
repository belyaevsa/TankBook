import XCTest

/// RV.38 - the inbox for work that finishes after the user moved on
/// (docs/JOURNEYS.md F4, amended). The decision is L1-tested
/// (`GatewayInboxPolicyTests`); this suite asserts the presentation and the
/// resolution the L1 layer cannot see:
///
/// - the bell carries a COUNT, and the entry keeps its OWN badge (hard rule 8:
///   the bell is a second route, never the only place a problem is visible);
/// - an item appears with its three actions;
/// - DECLINING leaves every field byte-identical - the assertion is the VALUES
///   (the derived price still derived, the typed total and litres unchanged),
///   never "a dialog showed" (the trap named in docs/TASKS.md RV.38);
/// - ACCEPTING fills the blank price from the receipt and leaves the typed
///   total and litres alone (hard rule 13);
/// - the item clears and does not return.
///
/// `-seedInboxItem` seeds one fill-up with a BLANK price (the one gateway field
/// a saved fill-up can genuinely leave nil) plus a pending item whose reading
/// fills that price (1.500) and disagrees with the typed total (99.99). The
/// form DERIVES 1.679 from the typed total/litres while the price is nil, so
/// "accept wrote 1.500" is distinguishable from "the form derived 1.679" - the
/// accept assertion is not the vacuous one it would be if the receipt's price
/// equalled the derived one.
@MainActor
final class InboxUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase", "-skipWelcome", "-inboxReset",
            "-seedSettingsSignedIn", "-seedInboxItem",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + arguments
        app.launch()
        return app
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    // MARK: - The bell carries a count, and the entry keeps its own badge

    func testBellShowsTheCountAndTheEntryKeepsItsOwnBadge() {
        let app = launch()

        // The bell's count is the NUMBER, never a mere "something is here"
        // (asserting a badge exists is the vacuous trap named in the brief).
        let bell = app.buttons["inboxBellButton"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10),
                      "the bell must be on the header")
        XCTAssertEqual(bell.label, "1 item in inbox",
                       "the bell names the count, not a bare dot")

        // Hard rule 8: the entry keeps its OWN badge - the bell is a second
        // route, never the only place the offer is visible.
        XCTAssertTrue(app.buttons["inboxEntryBadge"].waitForExistence(timeout: 5),
                      "the entry must carry its own badge while an item is pending")
    }

    // MARK: - An item appears with its three actions

    func testItemAppearsWithItsThreeActions() {
        let app = launch()
        app.buttons["inboxBellButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["inboxItemCard"].waitForExistence(timeout: 5),
                      "the pending item must render as a card")
        XCTAssertTrue(app.buttons["inboxUpdateButton"].exists,
                      "the 'update from the receipt' action must be present")
        XCTAssertTrue(app.buttons["inboxLeaveButton"].exists,
                      "the 'leave it as it is' action must be present (the default)")
        XCTAssertTrue(app.buttons["inboxReplaceButton"].exists,
                      "the 'replace the receipt' action must be present")
    }

    // MARK: - Declining leaves every field byte-identical

    func testDecliningLeavesEveryFieldByteIdentical() {
        let app = launch()

        // Record the entry's values BEFORE resolving: the price is nil, so the
        // form derives 1.679 from the typed 71.02 / 42.30.
        app.buttons["logEntryButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "71.02")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "1.679",
                       "the nil price derives from total/litres until the receipt fills it")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Decline in the inbox - "leave it as it is" is the default.
        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxLeaveButton"].waitForExistence(timeout: 5))
        app.buttons["inboxLeaveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "declining clears the item")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The entry is byte-identical: the receipt's 1.500 did NOT land, the
        // price is still derived 1.679, and the typed values are untouched.
        app.buttons["logEntryButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "71.02",
                       "a declined update must not touch the typed total")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30",
                       "a declined update must not touch the typed litres")
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "1.679",
                       "a declined update must not write the receipt's price")
    }

    // MARK: - Accepting fills the blank and leaves the typed values alone

    func testAcceptingFillsTheBlankPriceAndLeavesTypedValuesAlone() {
        let app = launch()

        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxUpdateButton"].waitForExistence(timeout: 5))
        app.buttons["inboxUpdateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "accepting clears the item")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The blank (nil) price is filled from the receipt (1.500) - it is no
        // longer the derived 1.679 - and the typed total and litres are theirs.
        app.buttons["logEntryButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpPricePerLField"), "1.500",
                       "the receipt's price fills the blank, not the derived value")
        XCTAssertEqual(fieldValue(app, "manualFillUpTotalField"), "71.02",
                       "an accepted update must not overwrite the typed total")
        XCTAssertEqual(fieldValue(app, "manualFillUpLitersField"), "42.30",
                       "an accepted update must not overwrite the typed litres")
    }

    // MARK: - The item clears and does not return

    func testItemClearsAndDoesNotReturn() {
        let app = launch()

        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxLeaveButton"].waitForExistence(timeout: 5))
        app.buttons["inboxLeaveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5))

        // Leave the inbox and come back: the resolved item must not return.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "a resolved item must not reappear")
        // The bell's count is gone: it reads "Inbox" again, never a stale number.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons["inboxBellButton"].label, "Inbox",
                       "the bell count must clear once the item is resolved")
    }

    // MARK: - The REAL flow: an answer that lands after save reaches the inbox

    /// The end-to-end proof of the durability shape: the sheet is saved and
    /// dismissed, the session is torn down with it, and yet the late answer -
    /// arriving after save - lands in the inbox. This pins the `markSaved`
    /// hand-off that survives the sheet's dismissal (the monitor's `[weak self]`
    /// cannot deliver a saved answer).
    func testALateAnswerThatLandsAfterSaveReachesTheInbox() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase", "-skipWelcome", "-inboxReset",
            "-seedSettingsSignedIn", "-seedVehicleForUITests",
            "-presentScreen", "confirmManual", "-seedConfirmPrefillLocked",
            "-seedGateway", "-seedGatewayDelay", "8",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        // Save immediately: the locked prefill is already a complete fill-up,
        // so the sheet can save before the 8 s answer arrives.
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled, "the locked prefill must be saveable")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving must leave the Confirm sheet")

        // The answer lands at 8 s, after the sheet is gone. The inbox records
        // it - the bell counts it, and the count is the NUMBER.
        let bell = app.buttons["inboxBellButton"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        let counted = NSPredicate(format: "label == %@", "1 item in inbox")
        expectation(for: counted, evaluatedWith: bell)
        waitForExpectations(timeout: 20)
    }
}
