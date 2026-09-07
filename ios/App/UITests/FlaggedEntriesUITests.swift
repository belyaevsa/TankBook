import XCTest

/// RV.72 - the "Needs a look" list must stop showing an entry the user has
/// fixed (hard rule 8: a fix that still reads as flagged is read as "my
/// correction was lost"). The screen is a pushed destination that stays alive
/// in the NavigationStack, so its one-shot `.task` does not re-fire on a
/// pop-back from Edit entry: the list re-reads when the toast-center revision
/// changes (a save anywhere), never because it was re-entered.
///
/// The pop-back path is the whole test: fixing an entry and landing back on
/// the SAME list instance (never Settings) must drop the fixed row and - when
/// the fixed row was the last one - reach the empty state. Re-entering the
/// screen from Settings would pass against the live bug, so no test here does.
@MainActor
final class FlaggedEntriesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    /// Settings seeded with two flagged fills, so the "N entries need a look"
    /// row is present and its tap reaches the account-wide list.
    private func openFlaggedList() -> XCUIApplication {
        let app = launch(["-presentScreen", "settings", "-seedSettingsFlagged"])
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the seeded flagged state must show the Settings row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10),
                      "the flagged row must open the filtered Log")
        return app
    }

    /// Waits until the list shows exactly `count` flagged rows. The reload is a
    /// `.task` that lands a beat after the pop-back animation, so an immediate
    /// `.count` assertion would sample mid-reload and flake.
    private func waitForFlaggedRowCount(_ count: Int, in app: XCUIApplication) {
        let rows = app.buttons.matching(identifier: "flaggedEntryRow")
        let predicate = NSPredicate { _, _ in rows.count == count }
        let expectation = expectation(for: predicate, evaluatedWith: rows)
        wait(for: [expectation], timeout: 10)
    }

    /// Opens the flagged row at `index`, fixes the entry (the save re-stamps
    /// the conflict from the timeline validator, which clears the seeded flag)
    /// and lands back on the list via the edit screen's own pop-back.
    private func fixFlaggedEntry(at index: Int, in app: XCUIApplication) {
        let rows = app.buttons.matching(identifier: "flaggedEntryRow")
        rows.element(boundBy: index).tap()
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10),
                      "a flagged row must open the entry's Edit screen")
        save.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10),
                      "saving the edit must pop back to the flagged list, never Settings")
    }

    /// The acceptance in one flow: fix an entry, pop back, the fixed row is
    /// gone; fix the last one, the empty state shows - not a row count.
    func testFixingTheLastFlaggedEntryReachesTheEmptyStateOnPopBack() {
        let app = openFlaggedList()
        waitForFlaggedRowCount(2, in: app)
        let firstLabel = app.buttons.matching(identifier: "flaggedEntryRow").firstMatch.label

        fixFlaggedEntry(at: 0, in: app)
        waitForFlaggedRowCount(1, in: app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", firstLabel))
            .firstMatch.exists,
            "the specific fixed row must be the one gone after the pop-back")

        fixFlaggedEntry(at: 0, in: app)
        waitForFlaggedRowCount(0, in: app)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "flaggedEntriesEmptyState").firstMatch
            .waitForExistence(timeout: 10),
            "after fixing the last flagged entry the list must reach its empty state")
        XCTAssertTrue(app.navigationBars["Needs a look"].exists,
                      "the empty state renders on the flagged list itself, not elsewhere")
    }

    /// The reason the fix observes the REVISION rather than the appearance.
    ///
    /// A pop-back fires `.onAppear` too, so the flow above passes against an
    /// appear-only reload - the orchestrator's mutation proved exactly that,
    /// leaving the suite green. Here the data changes **while the list stays on
    /// screen** and nothing appears: only a revision observer sees it. This is
    /// the sync-merge and Inbox case in miniature.
    func testAResolutionWhileTheListStaysOnScreenRemovesTheRow() {
        let app = launch(["-presentScreen", "settings", "-seedSettingsFlagged",
                          "-resolveFlaggedInPlace"])
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10))

        waitForFlaggedRowCount(2, in: app)
        // The seam resolves one entry in place and bumps the revision; no
        // navigation happens, so nothing appears and nothing re-enters.
        waitForFlaggedRowCount(1, in: app)
    }

    // MARK: - RV.89 the flagged list must say which year

    /// The "needs a look" list spans the account's whole log, so it mixes
    /// years - exactly the product owner's report (a flagged 2015 entry was
    /// indistinguishable from a flagged 2026 one, all reading "3 Jun"). The
    /// seeded list holds one flagged entry dated TODAY (always the current
    /// year) and one dated 380 days back (always a previous year): the older
    /// row's subtitle must carry the year and this year's must not. The year is
    /// asserted structurally on the rendered subtitle - never a bare "contains
    /// 24" (RV.89's named trap). Runs pinned to en_US, where a two-digit year
    /// renders as ", YY".
    func testMultiyearFlaggedListShowsYearOnTheOlderRowOnly() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsFlaggedMultiyear",
                               "-presentScreen", "settings",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10))
        waitForFlaggedRowCount(2, in: app)

        let subtitles = app.staticTexts.matching(identifier: "flaggedEntrySubtitle")
        let labels = subtitles.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels.count, 2,
                       "the two seeded flagged entries must render their subtitles")

        // Exactly one subtitle carries a rendered ", YY" two-digit year...
        let yearSuffix = ", ([0-9]{2})$"
        let withYear = labels.filter { firstCapture(yearSuffix, in: $0) != nil }
        XCTAssertEqual(withYear.count, 1,
                       "exactly the previous-year row must show a year, got \(labels)")
        let expectedYY = twoDigitYear(of: Date().addingTimeInterval(-380 * 86_400))
        XCTAssertEqual(firstCapture(yearSuffix, in: withYear[0]), expectedYY,
                       "the older row must carry the exact two-digit year of its date")

        // ...and the other subtitle ends in a bare month + day.
        let withoutYear = labels.first { firstCapture(yearSuffix, in: $0) == nil }!
        XCTAssertNotNil(firstCapture("[A-Za-z]{3} [0-9]{1,2}$", in: withoutYear),
                        "this year's flagged row must render no year, got '\(withoutYear)'")
    }

    // MARK: - RV.104 accepting a flagged entry

    /// The RV.104 path: a flagged entry from years back can be a gap nobody
    /// remembers - no fix can heal it without inventing history, and before
    /// this row the ONLY way to clear its flag was to falsify the odometer or
    /// date. Accept records the user's deliberate per-entry judgement and
    /// clears the derived flag; the count (derived, hard rule 2) drops by
    /// exactly the accepted row, reaches ZERO when the last one is accepted -
    /// the state the owner could not reach before - and Settings' own copy of
    /// the count goes with it. The specific accepted row is asserted gone, not
    /// merely the count falling (a vacuous-trap named in the row).
    func testAcceptingFlaggedEntriesDropsTheCountAndReachesZero() {
        let app = openFlaggedList()
        waitForFlaggedRowCount(2, in: app)

        let subtitles = app.staticTexts.matching(identifier: "flaggedEntrySubtitle")
        let firstSubtitle = subtitles.element(boundBy: 0).label

        let acceptButtons = app.buttons.matching(identifier: "flagAcceptButton")
        XCTAssertEqual(acceptButtons.count, 2,
                       "each flagged row must carry its own Accept affordance")
        acceptButtons.element(boundBy: 0).tap()
        let alert = app.alerts["Accept this entry?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the Accept affordance must ask before it acts (per entry, deliberate)")
        alert.buttons["Accept"].tap()

        waitForFlaggedRowCount(1, in: app)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@", firstSubtitle))
            .firstMatch.exists,
            "the ACCEPTED row must be the one gone - a bare count fall could be the wrong entry")

        app.buttons.matching(identifier: "flagAcceptButton").element(boundBy: 0).tap()
        let lastAlert = app.alerts["Accept this entry?"]
        XCTAssertTrue(lastAlert.waitForExistence(timeout: 5))
        lastAlert.buttons["Accept"].tap()

        waitForFlaggedRowCount(0, in: app)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "flaggedEntriesEmptyState").firstMatch
            .waitForExistence(timeout: 10),
            "accepting the last flagged entry must reach the empty state - the count is zero")

        // Settings' copy of the count is derived from the same rows: the row is
        // gone when we land back on Settings (it renders only while the count
        // is non-zero).
        app.navigationBars.buttons.firstMatch.tap()
        let settingsRow = app.buttons["settingsFlaggedRow"]
        let gone = NSPredicate { _, _ in !settingsRow.exists }
        wait(for: [expectation(for: gone, evaluatedWith: settingsRow)], timeout: 10)
    }

    // MARK: - Helpers

    /// The first regex capture group in `text` (the whole match when the
    /// pattern has no group). Date labels are asserted by SHAPE, never by a
    /// bare substring.
    private func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        if match.numberOfRanges > 1, let group = Range(match.range(at: 1), in: text) {
            return String(text[group])
        }
        guard let whole = Range(match.range, in: text) else { return nil }
        return String(text[whole])
    }

    /// The two-digit year a date must render under the formatter ("25" for
    /// 2025), computed the same way the row renders it.
    private func twoDigitYear(of date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.year, from: date) % 100)
    }
}
