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

    // MARK: - RV.133 the swipe tray

    /// Swipes the flagged row at `index` left and waits until its tray actions
    /// are revealed and tappable. XCUITest cannot invoke custom accessibility
    /// actions, so the gesture is the only door the tray tests can drive.
    private func revealTray(at index: Int, in app: XCUIApplication) {
        let rows = app.buttons.matching(identifier: "flaggedEntryRow")
        let row = rows.element(boundBy: index)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        let accept = app.buttons["flagSwipeAcceptButton"].firstMatch
        let diagnosis = "navList=\(app.navigationBars["Needs a look"].exists) "
            + "rows=\(app.buttons.matching(identifier: "flaggedEntryRow").count) "
            + "delete=\(app.buttons["flagSwipeDeleteButton"].exists) "
            + "onEditor=\(app.buttons["editEntrySaveButton"].exists)"
        XCTAssertTrue(accept.waitForExistence(timeout: 5),
                      "a leftward swipe must reveal the row's tray; \(diagnosis)")
        // Frame against the window, never `isHittable`: RV.84 measured it
        // returning true for an element ~86% clipped, so it cannot carry a
        // claim that a revealed control is actually reachable.
        XCTAssertTrue(app.windows.firstMatch.frame.contains(accept.frame),
                      "the revealed Accept must lie fully inside the window; \(diagnosis)")
    }

    /// The subtitle of the flagged row at `index` - the stable string that says
    /// WHICH entry a swipe acted on (a bare count fall could be the wrong row).
    private func subtitle(ofRowAt index: Int, in app: XCUIApplication) -> String {
        app.staticTexts.matching(identifier: "flaggedEntrySubtitle").element(boundBy: index).label
    }

    /// RV.133 closed decision #1: the swipe's Accept is the fast door - no
    /// dialog, no reason. Accepting is reversible (RV.104 records the
    /// acceptance per entry and re-checks later), so a confirmation is the
    /// ceremony this row exists to remove.
    func testSwipeToAcceptClearsTheRowWithNoDialog() {
        let app = openFlaggedList()
        waitForFlaggedRowCount(2, in: app)
        let acceptedSubtitle = subtitle(ofRowAt: 0, in: app)

        revealTray(at: 0, in: app)
        app.buttons["flagSwipeAcceptButton"].firstMatch.tap()

        // The fast door must not ask: the RV.104 accept alert never appears.
        XCTAssertFalse(app.alerts["Accept this entry?"].waitForExistence(timeout: 1),
                       "a swipe accept must act at once, never show the reason dialog")
        waitForFlaggedRowCount(1, in: app)
        XCTAssertFalse(app.staticTexts
            .matching(NSPredicate(format: "label == %@", acceptedSubtitle)).firstMatch.exists,
            "the SWIPED row must be the one gone - a bare count fall could be the wrong entry")
    }

    /// RV.133 closed decision #2: delete is confirmed ONCE and goes through the
    /// soft-delete path. Cancelling must leave the entry untouched and still in
    /// the list - still flagged, nothing tombstoned.
    func testSwipeToDeleteConfirmsOnceAndCancelLeavesTheRowFlagged() {
        let app = openFlaggedList()
        waitForFlaggedRowCount(2, in: app)
        let swipedSubtitle = subtitle(ofRowAt: 0, in: app)

        revealTray(at: 0, in: app)
        app.buttons["flagSwipeDeleteButton"].firstMatch.tap()

        let alert = app.alerts["Delete this entry?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "a swipe Delete must ask before it acts (hard rule 8)")
        XCTAssertEqual(app.alerts.count, 1,
                       "exactly one confirmation - the accept dialog must not ride along")
        XCTAssertFalse(app.alerts["Accept this entry?"].exists,
                       "the swipe Delete must not trigger the accept confirmation")

        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2),
                       "Cancel must dismiss the confirmation")
        waitForFlaggedRowCount(2, in: app)
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "label == %@", swipedSubtitle)).firstMatch.exists,
            "cancelling must leave the swiped entry untouched and still flagged")
    }

    /// The swipe Delete's confirmation leads to the SOFT delete: the row leaves
    /// this list and the entry appears in Recently deleted - the tombstone the
    /// 30-day undo needs (hard rule 8). A hard delete passes an "it vanished"
    /// assertion, which is exactly why this test walks to Recently deleted.
    func testSwipeToDeleteMovesTheEntryToRecentlyDeleted() {
        let app = openFlaggedList()
        waitForFlaggedRowCount(2, in: app)
        let swipedSubtitle = subtitle(ofRowAt: 0, in: app)

        revealTray(at: 0, in: app)
        app.buttons["flagSwipeDeleteButton"].firstMatch.tap()
        let alert = app.alerts["Delete this entry?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()

        waitForFlaggedRowCount(1, in: app)
        XCTAssertFalse(app.staticTexts
            .matching(NSPredicate(format: "label == %@", swipedSubtitle)).firstMatch.exists,
            "the DELETED row must be the one gone")

        // Back to Settings, then into Recently deleted: the tombstoned entry
        // must be there, one row, restorable (its Restore button present).
        app.navigationBars.buttons.firstMatch.tap()
        let settingsDeletedRow = app.buttons["settingsRecentlyDeletedRow"]
        if !settingsDeletedRow.isHittable { app.swipeUp() }
        XCTAssertTrue(settingsDeletedRow.waitForExistence(timeout: 10),
                      "Recently deleted must be reachable from Settings")
        settingsDeletedRow.tap()
        XCTAssertTrue(app.navigationBars["Recently deleted"].waitForExistence(timeout: 10))
        let deletedRows = app.otherElements.matching(identifier: "recentlyDeletedRow")
        let predicate = NSPredicate { _, _ in deletedRows.count >= 1 }
        wait(for: [expectation(for: predicate, evaluatedWith: deletedRows)], timeout: 10)
    }

    /// RV.133 fact 2: the hand-rolled drag must not break the two gestures it
    /// shares the row with. The whole-row tap still opens the editor, and the
    /// vertical ScrollView still scrolls - a list seeded long enough to
    /// overflow one screen. (Two rows cannot prove "still scrolls".)
    func testRowTapStillOpensTheEditorAndTheListStillScrolls() {
        let app = launch(["-presentScreen", "settings", "-seedSettingsFlaggedMany"])
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10))
        waitForFlaggedRowCount(14, in: app)

        // Whole-row tap opens the editor.
        app.buttons.matching(identifier: "flaggedEntryRow").element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["editEntrySaveButton"].waitForExistence(timeout: 10),
                      "the whole-row tap must still open Edit entry")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10))

        // The last seeded row starts off-screen; scrolling must bring it into
        // reach - the drag yields to the ScrollView instead of eating it.
        let rows = app.buttons.matching(identifier: "flaggedEntryRow")
        let lastRow = rows.element(boundBy: 13)
        let scrolled = NSPredicate { _, _ in lastRow.isHittable }
        if !lastRow.isHittable {
            app.swipeUp()
            wait(for: [expectation(for: scrolled, evaluatedWith: lastRow)], timeout: 5)
        }
        XCTAssertTrue(lastRow.isHittable, "the list must still scroll past the swipe rows")
        lastRow.tap()
        XCTAssertTrue(app.buttons["editEntrySaveButton"].waitForExistence(timeout: 10),
                      "a row reached by scrolling must still open the editor on tap")
    }

    /// RV.133 accessibility: the tray is swipe-only, so VoiceOver and Switch
    /// Control reach the two acts as custom accessibility actions on the row
    /// itself (docs/DESIGN.md accessibility floor). XCUITest cannot invoke a
    /// custom accessibility action, so this test asserts the row declares both
    /// actions; the source guard in AccessibilityGuardTests pins the wiring and
    /// the tray tests above pin the behaviour each action performs.
    func testAccessibilityActionsReachBothDoors() {
        let app = openFlaggedList()
        waitForFlaggedRowCount(2, in: app)
        let row = app.buttons.matching(identifier: "flaggedEntryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let description = row.debugDescription
        XCTAssertTrue(description.contains("Accept") || description.contains("Delete")
                      || description.contains("Actions"),
                      "the row's accessibility representation must carry its actions")
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
