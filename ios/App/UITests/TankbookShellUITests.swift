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

    /// Deterministic start state for every shell walk: a reset database, a
    /// signed-in session (`-seedSettingsSignedIn`) and a car with no entries.
    /// Home then shows the empty-entries card (the `editEntryButton` link), the
    /// header affordances (gear, car switcher, type it) and the Garage tab's
    /// links all exist. The session is not decoration: since PJ.3 a no-session
    /// launch renders the guest chrome, which has no `editEntryButton` or
    /// `carSwitcherButton`, so the shell walks would be order-dependent on
    /// whatever session a previous test left behind. Without the reset the shell
    /// tests would likewise depend on the previous test's database - a latent
    /// isolation bug P1.9's suite exposed.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomeEmptyVehicle"]
        app.launch()
        return app
    }

    // MARK: - Tab roots

    func testThreeTabRootsExist() {
        let app = launch()
        XCTAssertTrue(app.buttons["tabbar.log"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tabbar.trends"].exists)
        XCTAssertTrue(app.buttons["tabbar.garage"].exists)
    }

    /// The owned bar (P2.1b) replaces the system bar, which is hidden with
    /// `.toolbar(.hidden, for: .tabBar)`. This is the risk-detection assertion:
    /// our `tabbar.log` button is present and no system tab-bar item with the
    /// same label exists. If a future OS stops honouring the hide, the system
    /// bar reappears and this fails (the fallback is documented in AppTabBar).
    func testSystemTabBarIsHidden() {
        let app = launch()
        XCTAssertTrue(app.buttons["tabbar.log"].waitForExistence(timeout: 10),
                      "the owned bar's Log button must be present")
        XCTAssertFalse(app.tabBars.buttons["Log"].exists,
                       "the system tab bar must be hidden, not doubled under the owned bar")
    }

    func testTabRootsHaveNoBackButton() {
        let app = launch()
        XCTAssertTrue(app.buttons["tabbar.log"].waitForExistence(timeout: 10))
        // A tab root is a root: there is nothing to pop, so no back chevron.
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)

        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)

        app.buttons["tabbar.garage"].tap()
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
        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))

        // Switch back: the pushed Settings screen must still be on the stack.
        app.buttons["tabbar.log"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Edge walk (back paths)

    /// PJ.3: the Welcome root's three paths are edges too, and each has a back
    /// path (SCREENMAP rule zero - no dead ends). A fresh install shows Welcome
    /// (`-presentWelcome` runs the real onboarding decision under the seed
    /// harness's reset); every path returns to it.
    func testWelcomePathsHaveBackPaths() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentWelcome"]
        app.launch()

        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10))

        // Welcome -> Add car -> back -> Welcome
        app.buttons["welcomeAddCarButton"].tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 5))

        // Welcome -> Import -> back -> Welcome
        app.buttons["welcomeImportButton"].tap()
        // The wizard draws its own header (no system nav bar), so its own
        // title is the landing marker and its own close is the back path.
        XCTAssertTrue(app.staticTexts["importSourceTitle"].waitForExistence(timeout: 5))
        app.buttons["importSourceClose"].tap()
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 5))

        // Welcome -> Sign in -> Not now -> Welcome
        app.buttons["welcomeSignInButton"].tap()
        XCTAssertTrue(app.buttons["signInAppleButton"].waitForExistence(timeout: 5))
        app.buttons["signInNotNowButton"].tap()
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 5),
                      "declining sign-in must return to Welcome")
    }

    func testHomeTabEdgesHaveBackPaths() {
        let app = launch()

        // gear -> Settings -> back
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
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
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))

        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))

        app.buttons["garageAddCar"].tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    func testSettingsChainHasBackPaths() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // The real Settings screen (P4.9b) is taller than the P1.1 placeholder:
        // About and Recently deleted sit below the fold, so scroll them into
        // reach before tapping.
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))

        // Settings -> Recently deleted -> back
        let recentlyDeleted = app.buttons["settingsRecentlyDeletedRow"]
        scrollTo(recentlyDeleted, in: scroll)
        recentlyDeleted.tap()
        XCTAssertTrue(app.navigationBars["Recently deleted"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Settings -> About -> back
        let about = app.buttons["settingsAboutRow"]
        scrollTo(about, in: scroll)
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// Scrolls the Settings list until `element` is hittable (the same
    /// defensive pattern as `ConfirmManualUITests`: a tap on a covered row
    /// misses, and the failure reads like a missing element).
    private func scrollTo(_ element: XCUIElement, in scroll: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            scroll.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) is on screen but not reachable")
    }

    // MARK: - Sheet dismissal (explicit close)

    func testCarSwitcherSheetDismissesSilently() {
        let app = launch()
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "carSwitcherButton never appeared")
        switcher.tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))

        app.buttons["sheetCloseButton"].tap()

        // Dismissed with no prompt (scanned/picked data discards silently).
        XCTAssertFalse(app.navigationBars["My garage"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Discard changes?"].exists)
    }
}
