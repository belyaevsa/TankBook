import XCTest

/// PJ.3 Welcome root UI tests (docs/SCREENMAP.md -> Welcome): a fresh install
/// shows one screen with three hittable paths, each lands on its screen, and
/// Welcome never reappears once a car exists. `-presentWelcome` makes the
/// launch run the REAL onboarding decision even under the seed harness's
/// `-homeResetDatabase` (which otherwise signals "the tabbed app, not
/// onboarding") - it forces no outcome, so a vehicle or session still
/// suppresses Welcome.
@MainActor
final class WelcomeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    // MARK: - The screen and its three paths

    func testFreshInstallShowsWelcomeWithThreeHittablePaths() {
        let app = launch(["-presentWelcome"])

        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["welcomeImportButton"].exists)
        XCTAssertTrue(app.buttons["welcomeSignInButton"].exists)

        // The hero tagline is user-facing copy a future change could silently
        // drift. Assert the exact sentence, verbatim, so a later rewrite cannot
        // re-promise the hero without this test (and its screenshot) failing.
        XCTAssertTrue(app.staticTexts["Fuel, charging and service – one log"].waitForExistence(timeout: 5))

        // All three paths are real doors, not decoration (hard rule 15).
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].isHittable)
        XCTAssertTrue(app.buttons["welcomeImportButton"].isHittable)
        XCTAssertTrue(app.buttons["welcomeSignInButton"].isHittable)
    }

    func testAddCarPathLandsOnAddCar() {
        let app = launch(["-presentWelcome"])
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeAddCarButton"].tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))

        // Back returns to Welcome (SCREENMAP: AddVehicle -.-> X -> Welcome).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 5))
    }

    func testImportPathLandsOnImport() {
        let app = launch(["-presentWelcome"])
        XCTAssertTrue(app.buttons["welcomeImportButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeImportButton"].tap()
        // The wizard draws its own header (the system nav bar is hidden), so
        // the source screen's own title is the landing marker.
        XCTAssertTrue(app.staticTexts["importSourceTitle"].waitForExistence(timeout: 5))
    }

    func testSignInPathLandsOnSignInAndNotNowReturns() {
        let app = launch(["-presentWelcome"])
        XCTAssertTrue(app.buttons["welcomeSignInButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeSignInButton"].tap()

        // The sign-in sheet opens (the restore intent is carried by the third
        // path) and "Not now" returns to Welcome (SCREENMAP: SignIn -.-> Welcome).
        XCTAssertTrue(app.buttons["signInAppleButton"].waitForExistence(timeout: 10))
        app.buttons["signInNotNowButton"].tap()
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 5),
                      "declining sign-in from Welcome must return to Welcome")
    }

    // MARK: - Never again once a car exists

    /// Adding a car from Welcome ends onboarding for good: the guest Home takes
    /// over, and a later launch (same install, car still in the log) never
    /// offers Welcome again.
    func testWelcomeNeverReappearsOnceACarExists() {
        let app = launch(["-presentWelcome"])
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeAddCarButton"].tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))

        let name = app.textFields["addVehicleNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Volvo")
        app.buttons["addVehicleSaveButton"].tap()

        // The car exists: Welcome is gone and the guest Home owns the screen.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["welcomeAddCarButton"].exists,
                       "Welcome must leave the moment a car exists")

        // And it stays gone on the next launch - the gate reads the real log,
        // never a "has onboarded" flag that could be out of sync.
        app.terminate()
        app.launchArguments = ["-presentWelcome"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["welcomeAddCarButton"].exists,
                       "Welcome must never reappear once a car exists")
    }

    // MARK: - Restoring's cancel returns here (SCREENMAP rule zero)

    /// SCREENMAP.md:118: Restoring's *Cancel = sign out* lands back on Welcome -
    /// never a dead end. The restore state is the flow's own seeded scenario;
    /// the path is real (third path -> sign-in sheet).
    func testRestoringCancelReturnsToWelcome() {
        let app = launch(["-presentWelcome", "-signInRestore", "-signInStubAuth"])
        XCTAssertTrue(app.buttons["welcomeSignInButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeSignInButton"].tap()

        XCTAssertTrue(app.buttons["restoringOpenGarageButton"].waitForExistence(timeout: 10))
        app.buttons["restoringSignOutButton"].tap()

        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10),
                      "restoring's cancel must return to Welcome, not to a dead end")
        XCTAssertFalse(app.buttons["restoringOpenGarageButton"].exists,
                       "the sheet must be gone after the cancel")
    }
}
