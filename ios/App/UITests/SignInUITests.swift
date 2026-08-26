import XCTest

/// P4.4 sign-in flow UI tests. The two guarantees this screen exists to honour
/// (hard rule 1 and docs/JOURNEYS.md J11a): sign-in is optional and never
/// sync-gates anything, and the wrong-provider trap surfaces the honest question
/// with a one-tap switch and a sign-out escape - never an empty garage presented
/// as data loss.
@MainActor
final class SignInUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    /// Bring a field on screen, then tap it (the same defensive helper as
    /// `ConfirmManualUITests`: the three-number card can sit below the fold, and
    /// a tap on a covered field misses and the following `typeText` reads like a
    /// broken field).
    @discardableResult
    private func focusField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        var scrolls = 0
        while !field.isHittable && scrolls < 8 {
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
        return field
    }

    // MARK: - The wrong-provider trap (docs/JOURNEYS.md J11a)

    func testWrongProviderShowsHonestQuestionAndProviderSwitchIsOneTap() {
        let app = launch(["-presentScreen", "signIn", "-signInWrongProvider"])

        // The honest question renders, and the app did not skip straight to an
        // empty restore ("Open my garage") - never an empty garage presented as
        // data loss.
        let question = app.staticTexts[
            "Nothing is stored under this Apple ID. Last time, did you sign in with Google?"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["restoringOpenGarageButton"].exists,
                       "an empty account via restore must never present an empty garage")

        // Both next steps are one tap away: the switch and the sign-out escape.
        let switchButton = app.buttons["wrongProviderSwitchButton"]
        XCTAssertTrue(switchButton.exists && switchButton.isHittable)
        XCTAssertTrue(app.buttons["wrongProviderSignOutButton"].exists)

        // One tap switches provider: the flow re-runs with Google and the
        // question re-renders with the provider names flipped.
        switchButton.tap()
        let flipped = app.staticTexts[
            "Nothing is stored under this Google. Last time, did you sign in with Apple?"]
        XCTAssertTrue(flipped.waitForExistence(timeout: 10),
                      "the provider switch must be a single tap, not a re-entry")
    }

    // MARK: - The sign-out escape

    func testSignOutEscapeLeavesTheLocalAppIntact() {
        let app = launch(["-seedVehicleForUITests", "-presentScreen", "signIn", "-signInWrongProvider"])

        XCTAssertTrue(app.buttons["wrongProviderSignOutButton"].waitForExistence(timeout: 10))
        app.buttons["wrongProviderSignOutButton"].tap()

        // Back on the working app, and the seeded local car is still there -
        // signing out cleared only the session, never the local log.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["carSwitcherButton"].waitForExistence(timeout: 5),
                      "the local garage must survive the sign-out escape")
        XCTAssertFalse(app.staticTexts["Nothing is stored under this Apple ID. Last time, did you sign in with Google?"].exists)
    }

    // MARK: - Nothing is sync-gated (hard rule 1)

    func testSignInDeclinedLeavesLogTrendsGarageWorkingAndAnEntrySaves() {
        let app = launch(["-seedVehicleForUITests", "-presentScreen", "signIn"])

        // Decline sign-in at the decision moment.
        let notNow = app.buttons["signInNotNowButton"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        notNow.tap()

        // Log works.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        // Trends works.
        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))

        // Garage works.
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))

        // An entry saves: back to Log, type a fill-up, save.
        app.buttons["tabbar.log"].tap()
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()

        focusField(app, "manualFillUpTotalField").typeText("71.02")
        focusField(app, "manualFillUpLitersField").typeText("42.30")

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "two of three typed must enable save with no account")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
    }
}
