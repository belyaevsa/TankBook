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
}
