import XCTest

/// P1.10 Trends tests. The labels are the feature: the consumption tile must
/// state what its number is actually made of - "last 3 months" when the window
/// is satisfied, the REAL span when it extended ("last 5 months", never the
/// claimed three), and "first estimate · N fill cycles" below the floor. A tile
/// with nothing honest to show is omitted, never "N/A", "–" or "0.0". The
/// excluded footnote shows the engine's real count and routes to the flagged
/// entry.
@MainActor
final class TrendsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every test lands on the Trends tab at launch (`-selectTrendsTab`) and
    /// resets the database first so the states are isolated from each other.
    /// The language is explicit (EN) for the same reason as HomeUITests: a
    /// prior RU launch persists `-AppleLanguages` in the app's UserDefaults
    /// and would otherwise run this whole suite in Russian (P6.13).
    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-selectTrendsTab",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
        app.launch()
        return app
    }

    // MARK: - The honest labels (the deliverable)

    /// Two full tanks close exactly one segment: below the floor, so the tile
    /// carries "first estimate · 1 fill cycle" - the label says the number is
    /// provisional (docs/ERRORS.md -> Trends).
    func testFirstEstimateStateRendersItsLabel() {
        let app = launch(args: ["-seedHomeFirstEstimate"])

        XCTAssertTrue(anyElement(app, "trendsConsumptionTile").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["first estimate · 1 fill cycle"].waitForExistence(timeout: 5),
                      "the first-estimate wording is the feature - assert the text, not the presence")
    }

    /// Three segments but only two inside 90 days: the window extended and the
    /// label must say the REAL span (D3, docs/fixtures/consumption-golden.json).
    func testExtendedWindowStateRendersTheRealSpan() {
        let app = launch(args: ["-seedHomeExtendedWindow"])

        XCTAssertTrue(anyElement(app, "trendsConsumptionTile").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["last 5 months"].waitForExistence(timeout: 5),
                      "a number computed over five months must be labelled with its real span")

        // The consumption tile must NEVER claim the window it did not cover -
        // scoped to that tile, because the cost/km tile legitimately says
        // "last 3 months" about its own shorter data.
        let consumptionLabels = app.staticTexts
            .matching(identifier: "trendsConsumptionTile")
            .allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(consumptionLabels.contains("last 5 months"),
                      "the consumption tile's caption is the honest span, got \(consumptionLabels)")
        XCTAssertFalse(consumptionLabels.contains("last 3 months"),
                       "the extended span must never be labelled as the claimed window: \(consumptionLabels)")
    }

    /// A full five-month history satisfies the window: the label is the plain
    /// "last 3 months" and all four tiles render.
    func testFullHistoryRendersAllFourTilesWithWindowLabel() {
        let app = launch(args: ["-seedHomeFullHistory"])

        XCTAssertTrue(anyElement(app, "trendsConsumptionTile").waitForExistence(timeout: 10))
        XCTAssertTrue(anyElement(app, "trendsCostPerKmTile").exists)
        XCTAssertTrue(anyElement(app, "trendsSpendTile").exists)
        XCTAssertTrue(anyElement(app, "trendsPriceTile").exists)
        XCTAssertTrue(app.staticTexts["last 3 months"].waitForExistence(timeout: 5))
    }

    // MARK: - The excluded footnote (real count, routes to the flagged entry)

    func testExcludedFootnoteShowsRealCountAndRoutesToTheFlaggedEntry() {
        let app = launch(args: ["-seedHomeConflict"])

        let footnote = app.buttons["trendsExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10))
        XCTAssertTrue(footnote.label.contains("1 entry excluded"),
                      "the footnote must show the engine's real count, got '\(footnote.label)'")

        footnote.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5),
                      "tap -> the flagged entry (hard rule 7)")
    }

    // MARK: - P5.2b the F9 pending-rates footnote

    /// Trends footnotes the rate-pending entries too (docs/JOURNEYS.md F9:
    /// "entry shows original currency in trends with a footnote count"). The
    /// wording is the derived count with real plural rules; it is a hint, not
    /// a warning.
    func testPendingRatesFootnoteAppearsOnTrends() {
        let app = launch(args: ["-seedHomePendingRates", "-selectTrendsTab"])

        let footnote = app.staticTexts["trendsPendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10),
                      "Trends must footnote the rate-pending entries")
        XCTAssertTrue(footnote.label.contains("3 entries pending rates"),
                      "the footnote must show the derived count, got '\(footnote.label)'")
    }

    // MARK: - Omit, never fabricate

    func testDataPoorStateOmitsTilesAndNoNATiles() {
        let app = launch(args: ["-seedHomeEmptyVehicle"])

        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 10))
        XCTAssertFalse(anyElement(app, "trendsConsumptionTile").exists)
        XCTAssertFalse(anyElement(app, "trendsCostPerKmTile").exists)
        XCTAssertFalse(anyElement(app, "trendsSpendTile").exists)
        XCTAssertFalse(anyElement(app, "trendsPriceTile").exists)

        let forbidden = ["N/A", "–", "-", "0.0"]
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !forbidden.contains($0) },
                      "a placeholder tile rendered: \(labels)")
    }

    /// D4-shaped (one full tank, no segment): only the tiles with honest data
    /// render - spend and last price exist, consumption and cost/km do not.
    func testSingleFillShowsOnlyTheTilesThatHaveHonestData() {
        let app = launch(args: ["-seedHomeSingleFill"])

        XCTAssertTrue(anyElement(app, "trendsSpendTile").waitForExistence(timeout: 10))
        XCTAssertTrue(anyElement(app, "trendsPriceTile").exists)
        XCTAssertFalse(anyElement(app, "trendsConsumptionTile").exists,
                       "no segment yet - no consumption to show")
        XCTAssertFalse(anyElement(app, "trendsCostPerKmTile").exists,
                       "no km span yet - no cost/km to show")
    }

    // MARK: - P6.2 the J8 monthly-summary opt-in toggle

    /// The opt-in lives on Trends (docs/NOTIFICATIONS.md, "surfaced in
    /// Trends"), is OFF by default, and flips on with a tap. Permission is
    /// forced authorized so no dialog appears (the same `-notificationStatus`
    /// hook the Reminders tests use); the toggle's real decision - schedule vs
    /// cancel - is the core planner's job and is unit-tested there.
    func testMonthlySummaryToggleDefaultsOffAndFlipsOn() {
        let app = launch(args: ["-seedHomeFullHistory", "-notificationStatus", "authorized"])

        let toggle = app.switches["trendsMonthlySummaryToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the monthly-summary opt-in must surface on Trends")
        XCTAssertEqual(toggle.value as? String, "0",
                       "the J8 opt-in defaults OFF, got \(String(describing: toggle.value))")

        toggle.tap()
        let on = app.switches["trendsMonthlySummaryToggle"]
        XCTAssertEqual(on.value as? String, "1", "the toggle must flip on")
    }

    /// The preference persists across relaunches (it is the synced
    /// `Preferences.notifications.monthlySummary`). The second launch keeps the
    /// database (no `-homeResetDatabase`), so a toggle that only flipped
    /// in-memory would read back as OFF here.
    func testMonthlySummaryTogglePersistsAcrossRelaunch() {
        let app = launch(args: ["-seedHomeFullHistory", "-notificationStatus", "authorized"])
        let toggle = app.switches["trendsMonthlySummaryToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        XCTAssertEqual(app.switches["trendsMonthlySummaryToggle"].value as? String, "1")

        // Relaunch WITHOUT the database reset: the preference must read back ON.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-selectTrendsTab", "-notificationStatus", "authorized"]
        relaunched.launch()

        let persisted = relaunched.switches["trendsMonthlySummaryToggle"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 10))
        XCTAssertEqual(persisted.value as? String, "1",
                       "the monthly-summary preference must survive a relaunch")
    }

    // MARK: - PJ.5 the notification deep link (SCREENMAP.md -> the deep link)

    /// A tapped monthly-summary notification lands on the Trends tab - the
    /// identifier's family decides the destination. The launch default is the
    /// Log tab, so this proves the tap switched tabs. The selected-trait on the
    /// tab bar button is the ground truth: the inactive tabs' content stays in
    /// the accessibility tree (opacity is the tab switcher, not removal), so
    /// finding "Trends" content alone would not prove the tab was switched.
    func testReplayedMonthlySummaryTapLandsOnTrends() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeFullHistory",
                               "-replayNotificationResponse",
                               "monthly-summary.3F2504E0-4F89-41D3-9A0C-0305E82C3301.2026-08"]
        app.launch()

        let trendsTab = app.buttons["tabbar.trends"]
        XCTAssertTrue(trendsTab.waitForExistence(timeout: 10))
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: trendsTab)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["tabbar.log"].isSelected,
                       "the Log tab must not be selected after a monthly-summary tap")
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5),
                      "the Trends root is what is in frame, not a bare title")
    }

    // MARK: - Helpers

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
