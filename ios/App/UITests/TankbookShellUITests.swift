import XCTest

/// P1.1 shell tests: walks the SCREENMAP edges that exist in the shell and
/// asserts the dead-end audit holds (every reachable screen has a back path).
/// Also proves the single most important behaviour: switching tabs preserves
/// each tab's own navigation stack.
@MainActor
final class TankbookShellUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Deterministic start state for every shell walk: a reset database plus a
    /// car with no entries. Home then shows the empty-entries card (the
    /// `editEntryButton` link), the header affordances (gear, car switcher,
    /// type it) and the Garage tab's links all exist. Without the reset the
    /// shell tests would depend on whatever the PREVIOUS test left in the
    /// database - a latent isolation bug P1.9's suite exposed.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeEmptyVehicle"]
        app.launch()
        return app
    }

    // MARK: - Tab roots

    func testThreeTabRootsExist() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Trends"].exists)
        XCTAssertTrue(app.tabBars.buttons["Garage"].exists)
    }

    func testTabRootsHaveNoBackButton() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 10))
        // A tab root is a root: there is nothing to pop, so no back chevron.
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)

        app.tabBars.buttons["Trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)

        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)
    }

    // MARK: - Tab-stack preservation (the stated requirement)

    func testTabSwitchPreservesEachTabsPushedScreen() {
        let app = launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))

        // Push Settings on the Log tab.
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Switch away to Trends.
        app.tabBars.buttons["Trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))

        // Switch back: the pushed Settings screen must still be on the stack.
        app.tabBars.buttons["Log"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Edge walk (back paths)

    func testHomeTabEdgesHaveBackPaths() {
        let app = launch()

        // gear -> Settings -> back
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        // entry -> Edit entry -> back
        app.buttons["editEntryButton"].tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
    }

    func testGarageTabEdgesHaveBackPaths() {
        let app = launch()
        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))

        app.buttons["vehicleDetailButton"].tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))

        app.buttons["addVehicleButton"].tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    func testSettingsChainHasBackPaths() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Settings -> About -> back
        app.buttons["aboutButton"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Settings -> Recently deleted -> back (P1.7 replaced the placeholder
        // link with the real screen; Restore works in place on that screen and
        // is covered by RecentlyDeletedUITests).
        app.buttons["recentlyDeletedButton"].tap()
        XCTAssertTrue(app.navigationBars["Recently deleted"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Sheet dismissal (explicit close)

    func testCarSwitcherSheetDismissesSilently() {
        let app = launch()
        app.buttons["carSwitcherButton"].tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))

        app.buttons["sheetCloseButton"].tap()

        // Dismissed with no prompt (scanned/picked data discards silently).
        XCTAssertFalse(app.navigationBars["My garage"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Discard changes?"].exists)
    }
}
