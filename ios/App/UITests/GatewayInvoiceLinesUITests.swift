import XCTest

/// PJ.303 - every page reaches the cloud, and the cloud's lines are offered on
/// the split (docs/JOURNEYS.md J7 "every page reaches the cloud"). The rules
/// the suite pins:
///
/// 1. A two-page scan reaches `/extract` as ONE two-page request - the seeded
///    transport refuses any other page count (`-seedGatewayExpectPages`), so
///    a first-page-only call makes the answer never arrive and the test fail.
/// 2. Within the budget, a cloud line that differs from its paired local line
///    renders as an offer on THAT row; "take" swaps the row, and Save with
///    nothing tapped persists the local split unchanged (hard rule 13).
/// 3. A late reading lands in the inbox listing the same pairs.
///
/// The seeded reading (`-seedGatewayInvoiceLines`) differs from the local
/// split on purpose - a reading that matched line for line would render no
/// offer and prove nothing (the row's vacuous trap).
@MainActor
final class GatewayInvoiceLinesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GatewayInvoiceLinesUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")
            .appendingPathComponent("receipt-011-samara-diesel-ru.png")
            .path
    }

    /// A two-page service capture with the seeded cloud reading; the transport
    /// asserts both pages arrived.
    private func launch(_ seeds: [String], pages: Int = 2, russian: Bool = false) -> XCUIApplication {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture), "the corpus fixture is missing: \(fixture)")
        let app = XCUIApplication()
        app.launchArguments = [
            // `-inboxReset`: the inbox lives in UserDefaults and outlives the
            // database reset, so a previous suite's item would make the card
            // query ambiguous.
            "-homeResetDatabase", "-inboxReset", "-seedHomeEmptyVehicle",
            "-presentScreen", "capture", "-cameraStatus", "authorized",
            "-captureMode", "service", "-captureFixtureImage", fixture,
            "-captureAutoServiceScan", "-captureAutoServiceScanPages", String(pages), "-seedServiceScan",
            "-seedGateway", "-seedGatewayInvoiceLines", "-seedGatewayExpectPages", String(pages)
        ] + (russian ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] : []) + seeds
        app.launch()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 20),
                      "a service scan must land on the service entry form")
        return app
    }

    private func value(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].firstMatch.value as? String) ?? ""
    }

    // MARK: - Within the budget: the offer on the row

    /// The local split's one line (Brake pads front, 89.00) is paired by title
    /// with the cloud's "BRAKE PADS FRONT 95.00" and the offer renders on that
    /// row; the cloud's "Environmental fee" has no partner and renders as a
    /// new-line card; the reading's total (100.00) does not equal its lines
    /// (98.50), so the amber flag shows under the header total.
    private func offerRendersOnTheRow(language: String) {
        let app = launch(["-seedGatewayDelay", "0.5"], russian: language == "ru")

        let offer = app.staticTexts["serviceEntryLineOfferValue_0"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10),
                      "the differing cloud line must be offered on the form")
        XCTAssertTrue(offer.label.contains("BRAKE PADS FRONT"), "the offer names the cloud's line: \(offer.label)")
        XCTAssertTrue(offer.label.contains("95"), "the offer carries the cloud's amount: \(offer.label)")
        XCTAssertTrue(app.buttons["serviceEntryLineOfferTake_0"].exists, "take must be one tap away")
        XCTAssertTrue(app.buttons["serviceEntryLineOfferKeep_0"].exists, "keep must be one tap away")
        XCTAssertTrue(app.staticTexts["serviceEntryLineOfferValue_1"].exists,
                      "the cloud line no local line matches must render as a new line")
        XCTAssertTrue(app.descendants(matching: .any)["serviceEntryReadingDoesNotAddUp"].exists,
                      "a reading whose lines do not sum to its total must be flagged under the total")

        // The row itself is untouched until the user answers (keep by default).
        XCTAssertEqual(value(app, "serviceEntryItemTitle"), "Brake pads front")
        XCTAssertEqual(value(app, "serviceEntryItemCost"), "89.00")
        XCTAssertEqual(app.textFields.matching(identifier: "serviceEntryItemTitle").count, 1,
                       "a new-line offer must not join the split until accepted")
    }

    func testADifferingCloudLineIsOfferedOnItsRow() {
        offerRendersOnTheRow(language: "en")
    }

    func testADifferingCloudLineIsOfferedOnItsRowInRussian() {
        offerRendersOnTheRow(language: "ru")
    }

    /// Tapping "take" swaps the row's title and cost for the cloud's and the
    /// offer is answered; the header total follows the row (derived, hard rule 2).
    /// Scrolls a button clear of the pinned save bar, then taps it: a tap on
    /// a button the bar covers lands on the bar - and saves the form.
    private func tapClearOfSaveBar(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(identifier) never appeared")
        var swipes = 0
        while swipes < 6,
              !(button.isHittable && button.frame.maxY < app.buttons["serviceEntrySaveButton"].frame.minY - 8) {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        button.tap()
    }

    func testTakingTheOfferSwapsTheRow() {
        let app = launch(["-seedGatewayDelay", "0.5"])
        tapClearOfSaveBar(app, "serviceEntryLineOfferTake_0")

        XCTAssertEqual(value(app, "serviceEntryItemTitle"), "BRAKE PADS FRONT",
                       "take must replace the row's title with the invoice's")
        XCTAssertEqual(value(app, "serviceEntryItemCost"), "95.00",
                       "take must replace the row's cost with the invoice's")
        XCTAssertFalse(app.staticTexts["serviceEntryLineOfferValue_0"].exists,
                       "an answered offer leaves the row")
        XCTAssertTrue(app.staticTexts["serviceEntryHeaderTotal"].label.contains("95"),
                      "the header total is derived from the swapped row")

        tapClearOfSaveBar(app, "serviceEntryLineOfferTake_1")
        let second = app.textFields.matching(identifier: "serviceEntryItemTitle").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5), "accepting the new line appends it to the split")
        XCTAssertEqual((second.value as? String) ?? "", "Environmental fee")
        XCTAssertTrue(app.staticTexts["serviceEntryHeaderTotal"].label.contains("98"),
                      "the header total follows the appended line: \(app.staticTexts["serviceEntryHeaderTotal"].label)")
    }

    /// Save with nothing tapped: the saved record is the local split, line for
    /// line - the offers changed nothing (hard rule 13's "keep mine" default).
    func testSavingWithNoOfferAnsweredPersistsTheLocalSplitUnchanged() {
        let app = launch(["-seedGatewayDelay", "0.5"])
        XCTAssertTrue(app.staticTexts["serviceEntryLineOfferValue_0"].waitForExistence(timeout: 10),
                      "the offer must be on screen before the save, or the test proves nothing")

        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let row = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the saved service must appear in the Log")
        row.tap()

        let title = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertTrue(title.firstMatch.waitForExistence(timeout: 15), "the reopened service shows its lines")
        XCTAssertEqual(title.count, 1, "the unaccepted new line must not have been saved")
        XCTAssertEqual((title.firstMatch.value as? String) ?? "", "Brake pads front",
                       "an unanswered offer must not change the saved line")
        XCTAssertEqual((app.textFields["editEntryServiceItemCost"].firstMatch.value as? String) ?? "", "89.00")
    }

    // MARK: - Late: the inbox lists the same pairs

    /// A reading that lands after the save reaches the inbox through the one
    /// policy; the card lists the cloud's first line against the user's own
    /// row ("Row 1", paired by title, never by position), the unpaired line as
    /// a new line, and the total with its "doesn't add up" flag.
    func testALateReadingLandsInTheInboxWithThePairs() {
        let app = launch(["-seedGatewayDelay", "8"])
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        let bell = app.buttons["inboxBellButton"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        XCTAssertTrue(app.buttons["inboxTick_lineItem_0"].waitForExistence(timeout: 40),
                      "the late reading's paired line must be offered on the card")
        XCTAssertTrue(app.buttons["inboxTick_lineItem_1"].exists, "the new line must be offered too")
        XCTAssertTrue(app.staticTexts["Row 1"].exists,
                      "the paired line is labelled by the USER'S row, counted from one (RV.216)")
        XCTAssertTrue(app.staticTexts["New line"].exists, "the unpaired line is labelled as new")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Brake pads front"))
                        .firstMatch.exists, "the 'yours' column shows the paired local line")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "BRAKE PADS FRONT"))
                        .firstMatch.exists, "the receipt column shows the cloud's line")
        XCTAssertTrue(app.staticTexts["inboxReadingDoesNotAddUp"].exists,
                      "the total offer must carry the arithmetic gate's flag")
        app.buttons["inboxLeaveButton"].tap()
    }

    // MARK: - Over the page cap

    /// More pages than the served cap: no cloud reading is started (no proceed
    /// note), every page is kept, and the form names the cap and the next step
    /// (docs/ERRORS.md -> Service & expenses). The seeded config caps at 2.
    func testAScanOverThePageCapKeepsEveryPageAndNamesTheCap() {
        let app = launch(["-seedConfigMaxInvoicePages", "2"], pages: 3)
        let note = app.descendants(matching: .any)["servicePageCapNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "the page-cap note must render on the form")
        XCTAssertTrue(note.label.contains("2"), "the note names the cap: \(note.label)")
        XCTAssertFalse(app.descendants(matching: .any)["gatewayProceedNote"].exists,
                       "no cloud reading was started, so no in-flight note")
        let counter = app.staticTexts["serviceEntryPageCounter"]
        XCTAssertTrue(counter.exists, "the page strip must be on screen")
        XCTAssertTrue(counter.label.contains("3"), "every captured page is kept on the strip: \(counter.label)")
        XCTAssertTrue(app.buttons["serviceEntrySaveButton"].isEnabled, "the local split still saves")
    }
}
