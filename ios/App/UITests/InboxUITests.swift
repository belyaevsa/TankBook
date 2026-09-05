import XCTest

/// RV.38 - the inbox for work that finishes after the user moved on
/// (docs/JOURNEYS.md F4, amended); RV.45 the per-field ask (amended 2026-09-04).
/// The decision is L1-tested (`GatewayInboxPolicyTests`); this suite asserts the
/// presentation and the resolution the L1 layer cannot see:
///
/// - the bell carries a COUNT, and the entry keeps its OWN badge (hard rule 8);
/// - a comparison item offers a tick PER FIELD the receipt read that differs or
///   fills a blank - exactly two ticks for the one-differing + one-blank seed;
/// - DECLINING leaves every field byte-identical;
/// - ticking only the blank fills it and leaves the differing field's VALUE
///   unchanged; ticking the differing field replaces only that field;
/// - a card with nothing to change says so and offers no update action;
/// - the item clears and does not return.
///
/// Seeds (InboxTestSeed): `-seedInboxItem` (rich: blank price + five differing
/// fields), `-seedInboxComparison` (exactly one differing field and one blank),
/// `-seedInboxNothingToChange` (the reading agrees). The comparison seed writes
/// total 100.00 / volume 40.00 with the price BLANK, and a receipt reading
/// volume 30.00 (differs) + price 1.800 (blank fill) - so "took the blank"
/// (price 1.800, litres still 40.00) is distinguishable from "took the volume"
/// (litres 30.00, price derived 100/30 = 3.333) by VALUE, never by "a thing
/// happened".
@MainActor
final class InboxUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase", "-skipWelcome", "-inboxReset",
            "-seedSettingsSignedIn",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + arguments
        app.launch()
        return app
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    private struct EntryValues {
        let total: String
        let liters: String
        let price: String
    }

    /// Opens the single seeded entry and returns its three number-field values.
    private func entryValues(_ app: XCUIApplication) -> EntryValues {
        app.buttons["logEntryButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        let values = EntryValues(
            total: fieldValue(app, "manualFillUpTotalField"),
            liters: fieldValue(app, "manualFillUpLitersField"),
            price: fieldValue(app, "manualFillUpPricePerLField")
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return values
    }

    // MARK: - The bell carries a count, and the entry keeps its own badge

    func testBellShowsTheCountAndTheEntryKeepsItsOwnBadge() {
        let app = launch(["-seedInboxItem"])

        let bell = app.buttons["inboxBellButton"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10),
                      "the bell must be on the header")
        XCTAssertEqual(bell.label, "1 item in inbox",
                       "the bell names the count, not a bare dot")

        XCTAssertTrue(app.buttons["inboxEntryBadge"].waitForExistence(timeout: 5),
                      "the entry must carry its own badge while an item is pending")
    }

    // MARK: - An item appears with its actions

    func testItemAppearsWithItsThreeActions() {
        let app = launch(["-seedInboxItem"])
        app.buttons["inboxBellButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["inboxItemCard"].waitForExistence(timeout: 5),
                      "the pending item must render as a card")
        XCTAssertTrue(app.buttons["inboxLeaveButton"].exists,
                      "the 'leave it as it is' action must be present (the default)")
        XCTAssertTrue(app.buttons["inboxUpdateButton"].exists,
                      "the update action must be present")
        XCTAssertFalse(app.buttons["inboxUpdateButton"].isEnabled,
                       "nothing is ticked, so update must not fire (a no-op action is hard rule 7)")
        XCTAssertTrue(app.buttons["inboxReplaceButton"].exists,
                      "the 'replace the receipt' action must be present")
    }

    // MARK: - RV.64 which act is loud follows the ticks, and never sticks

    /// The whole point of RV.64: WHICH act carries the prominent treatment must
    /// follow the tick count, and leave-as-is must not stay loud once the user
    /// has decided. The buttons' accessible VALUE carries the treatment
    /// ("primary" / "secondary"), produced by the same core decision the styling
    /// reads (`GatewayInboxPolicy.recommendedAction`), so this asserts the
    /// TREATMENT - not mere presence, not the enabled flag (which already moved
    /// before RV.64 and was the whole insufficiency), and never a colour literal.
    func testProminenceFollowsTheTicks() {
        let app = launch(["-seedInboxComparison"])
        app.buttons["inboxBellButton"].tap()

        let leave = app.buttons["inboxLeaveButton"]
        let update = app.buttons["inboxUpdateButton"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))

        // Zero ticks: nothing is decided yet, so leave-as-is stays the loud
        // default (hard rule 13) and the update is a disabled no-op.
        XCTAssertEqual(leave.value as? String, "primary",
                       "with nothing ticked, leave-as-is must carry the prominent treatment")
        XCTAssertEqual(update.value as? String, "secondary",
                       "with nothing ticked, the update must carry the secondary treatment")
        XCTAssertFalse(update.isEnabled,
                       "with nothing ticked the update is a no-op and must be disabled (hard rule 7)")

        // One tick: a ticked field IS the user deciding, so the update - the act
        // that honours the ticks - becomes prominent and leave-as-is dims (hard
        // rule 8: the loudest control must not be the one that discards the ticks).
        app.buttons["inboxTick_volume"].tap()
        XCTAssertEqual(update.value as? String, "primary",
                       "once a field is ticked, the UPDATE must carry the prominent treatment")
        XCTAssertEqual(leave.value as? String, "secondary",
                       "once a field is ticked, leave-as-is must drop to the dimmed treatment")
        XCTAssertTrue(update.isEnabled,
                      "a tick makes the update a real act, so it is enabled")

        // Symmetry: unticking the last field restores the default weighting.
        app.buttons["inboxTick_volume"].tap()
        XCTAssertEqual(leave.value as? String, "primary",
                       "unticking the last field must return the prominence to leave-as-is")
        XCTAssertEqual(update.value as? String, "secondary",
                       "the empty state is the same state, however it was reached")
    }

    // MARK: - The comparison offers a tick per decision, and only per decision

    func testComparisonCardOffersExactlyTwoTicks() {
        let app = launch(["-seedInboxComparison"])
        app.buttons["inboxBellButton"].tap()

        XCTAssertTrue(app.buttons["inboxTick_volume"].waitForExistence(timeout: 5),
                      "the differing volume must be tickable")
        XCTAssertTrue(app.buttons["inboxTick_unitPrice"].exists,
                      "the blank price must be tickable")
        XCTAssertFalse(app.buttons["inboxTick_total"].exists,
                       "an agreeing total is not a decision - no tick")
        XCTAssertFalse(app.buttons["inboxTick_date"].exists,
                       "an unread date is not a decision - no tick")
        XCTAssertFalse(app.buttons["inboxTick_fuelKind"].exists,
                       "an agreeing fuel kind is not a decision - no tick")
        XCTAssertFalse(app.buttons["inboxTick_currency"].exists,
                       "an agreeing currency is not a decision - no tick")
    }

    // MARK: - Ticking only the blank fills it and leaves the differing field alone

    func testTickingOnlyTheBlankLeavesTheDifferingFieldByteIdentical() {
        let app = launch(["-seedInboxComparison"])

        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxTick_unitPrice"].waitForExistence(timeout: 5))
        app.buttons["inboxTick_unitPrice"].tap()
        XCTAssertTrue(app.buttons["inboxUpdateButton"].isEnabled,
                      "a tick enables the update")
        app.buttons["inboxUpdateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "updating clears the item")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let values = entryValues(app)
        XCTAssertEqual(values.price, "1.800",
                       "the blank price fills from the receipt, not the derived 2.500")
        XCTAssertEqual(values.liters, "40.00",
                       "the differing volume is the user's own - taking only the blank must not move it")
        XCTAssertEqual(values.total, "100.00",
                       "the typed total is untouched")
    }

    // MARK: - Ticking the differing field replaces only that field

    func testTickingTheDifferingFieldReplacesOnlyThatField() {
        let app = launch(["-seedInboxComparison"])

        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxTick_volume"].waitForExistence(timeout: 5))
        app.buttons["inboxTick_volume"].tap()
        app.buttons["inboxUpdateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let values = entryValues(app)
        XCTAssertEqual(values.liters, "30.00",
                       "the receipt's volume replaces the typed 40.00")
        XCTAssertEqual(values.price, "3.333",
                       "the blank price was NOT taken - it re-derives from 100.00 / 30.00")
        XCTAssertEqual(values.total, "100.00",
                       "the typed total is untouched")
    }

    // MARK: - A card with nothing to change says so and offers no update

    func testNothingToChangeSaysSoAndOffersNoUpdateAction() {
        let app = launch(["-seedInboxNothingToChange"])
        app.buttons["inboxBellButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["inboxNothingToChange"].waitForExistence(timeout: 5),
                      "the card must state that nothing would change")
        XCTAssertFalse(app.buttons["inboxUpdateButton"].exists,
                       "an action that changes nothing must not be offered")
        XCTAssertTrue(app.buttons["inboxLeaveButton"].exists,
                       "leave-it-as-it-is still clears the item")
    }

    // MARK: - Declining leaves every field byte-identical

    func testDecliningLeavesEveryFieldByteIdentical() {
        let app = launch(["-seedInboxItem"])

        let before = entryValues(app)
        XCTAssertEqual(before.total, "71.02")
        XCTAssertEqual(before.liters, "42.30")
        XCTAssertEqual(before.price, "1.679",
                       "the nil price derives from total/litres until the receipt fills it")

        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxLeaveButton"].waitForExistence(timeout: 5))
        app.buttons["inboxLeaveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "declining clears the item")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let after = entryValues(app)
        XCTAssertEqual(after.total, before.total, "a declined update must not touch the typed total")
        XCTAssertEqual(after.liters, before.liters, "a declined update must not touch the typed litres")
        XCTAssertEqual(after.price, before.price, "a declined update must not write the receipt's price")
    }

    // MARK: - The item clears and does not return

    func testItemClearsAndDoesNotReturn() {
        let app = launch(["-seedInboxItem"])

        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.buttons["inboxLeaveButton"].waitForExistence(timeout: 5))
        app.buttons["inboxLeaveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["inboxBellButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "a resolved item must not reappear")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons["inboxBellButton"].label, "Inbox",
                       "the bell count must clear once the item is resolved")
    }

    // MARK: - The REAL flow: an answer that lands after save reaches the inbox

    /// The end-to-end proof of the durability shape: the sheet is saved and
    /// dismissed, the session is torn down with it, and yet the late answer -
    /// arriving after save - lands in the inbox.
    func testALateAnswerThatLandsAfterSaveReachesTheInbox() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase", "-skipWelcome", "-inboxReset",
            "-seedSettingsSignedIn", "-seedVehicleForUITests",
            "-presentScreen", "confirmManual", "-seedConfirmPrefillLocked",
            "-seedGateway", "-seedGatewayDelay", "8",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled, "the locked prefill must be saveable")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "saving must leave the Confirm sheet")

        let bell = app.buttons["inboxBellButton"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        let counted = NSPredicate(format: "label == %@", "1 item in inbox")
        expectation(for: counted, evaluatedWith: bell)
        waitForExpectations(timeout: 20)
    }
}
