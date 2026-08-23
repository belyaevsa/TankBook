import XCTest

/// P1.7 Recently deleted UI tests. The seed (`-seedRecentlyDeleted`) writes a
/// vehicle and three tombstoned entries - a Neste fill (27 days left), an
/// Ionity charge (19 days left) and a Car wash expense (4 days left on the run
/// date) - reproducing design/screens/RecentlyDeleted.dc.html. Everything
/// sync-shaped (`-forceSyncOverwritten`, `-forceRemovedElsewhere`) is a
/// fixture until P4.
@MainActor
final class RecentlyDeletedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", "recentlyDeleted"] + args
        app.launch()
        return app
    }

    private func restoreButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "recentlyDeletedRestoreButton")
    }

    private func textContaining(_ app: XCUIApplication, _ substring: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: - The list + Restore

    func testListShowsDeletedEntriesWithCountdownAndRestoreReturnsEntryToLog() {
        let app = launch(args: ["-seedRecentlyDeleted"])

        // Three tombstoned rows, each carrying its countdown (the screen's
        // point: how long the user has to change their mind).
        XCTAssertTrue(restoreButtons(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(restoreButtons(app).count, 3)
        XCTAssertTrue(textContaining(app, "27 days left").exists)
        XCTAssertTrue(textContaining(app, "19 days left").exists)
        XCTAssertTrue(textContaining(app, "4 days left").exists)
        // The rows show WHAT the entry was - title · quantity · amount.
        XCTAssertTrue(textContaining(app, "Neste · 51.1 L · 84.77").exists)

        // Restore the newest row (the Neste fill): it leaves this screen...
        restoreButtons(app).firstMatch.tap()
        XCTAssertEqual(restoreButtons(app).count, 2,
                       "restoring a row must remove it from the list")

        // ...and is back in the Log. The screen sits on the Log tab's stack,
        // so one back chevron lands on it.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5))
        let logRows = app.buttons.matching(identifier: "logEntryButton")
        XCTAssertEqual(logRows.count, 1,
                       "the restored entry must reappear in the Log")
        XCTAssertTrue(logRows.firstMatch.exists)
    }

    // MARK: - Delete all now (system confirmation)

    func testDeleteAllRaisesConfirmationAndCancelLeavesEverythingIntact() {
        let app = launch(args: ["-seedRecentlyDeleted"])

        let deleteAll = app.buttons["recentlyDeletedDeleteAllButton"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10))
        deleteAll.tap()

        // The system confirmation - the one place red lives.
        let alert = app.alerts["Delete everything here?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Delete all now"].exists)

        // Cancel: nothing is purged, all three rows stay.
        alert.buttons["Cancel"].tap()
        XCTAssertEqual(restoreButtons(app).count, 3,
                       "cancelling Delete all must leave every tombstone intact")
        XCTAssertFalse(anyElement(app, "recentlyDeletedEmptyState").exists)
    }

    func testDeleteAllConfirmsAndEmptiesTheScreen() {
        let app = launch(args: ["-seedRecentlyDeleted"])

        let deleteAll = app.buttons["recentlyDeletedDeleteAllButton"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10))
        deleteAll.tap()

        let alert = app.alerts["Delete everything here?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete all now"].tap()

        // Destructive confirmation worked: rows gone, the reassuring empty
        // state takes over - no fabricated rows.
        XCTAssertTrue(anyElement(app, "recentlyDeletedEmptyState").waitForExistence(timeout: 5))
        XCTAssertEqual(restoreButtons(app).count, 0)
    }

    // MARK: - Empty state

    func testEmptyStateRendersWithNoFabricatedRows() {
        let app = launch()

        // No deleted entries is the normal case: the screen says so plainly,
        // and renders no rows, no Restore affordances and no Delete-all.
        XCTAssertTrue(anyElement(app, "recentlyDeletedEmptyState").waitForExistence(timeout: 10))
        XCTAssertEqual(restoreButtons(app).count, 0)
        XCTAssertFalse(app.buttons["recentlyDeletedDeleteAllButton"].exists)
        XCTAssertFalse(app.buttons["recentlyDeletedCompareButton"].exists)
        XCTAssertTrue(app.staticTexts[
            "Deleted entries stay here for 30 days, then are removed permanently."].exists)
    }

    // MARK: - Overwritten by sync (fixture)

    func testOverwrittenBySyncSectionRendersWithCompareAffordance() {
        let app = launch(args: ["-seedRecentlyDeleted", "-forceSyncOverwritten"])

        // S1/S4's undo log row: the losing version, kept, with Compare.
        XCTAssertTrue(anyElement(app, "recentlyDeletedSyncRow").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recentlyDeletedCompareButton"].exists)
        XCTAssertTrue(textContaining(app, "your version from iPhone").exists)
        XCTAssertTrue(textContaining(app, "odometer differed").exists)
        // Its own countdown is present too ("Replaced <day> · ... · 28 days left").
        XCTAssertTrue(textContaining(app, "28 days left").exists)
    }
}
