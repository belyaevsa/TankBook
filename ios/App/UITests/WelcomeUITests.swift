import XCTest

/// PJ.3 Welcome root UI tests (docs/SCREENMAP.md -> Welcome): a fresh install
/// shows one screen with three hittable peer doors plus the returning user's
/// restore line, each lands on its screen, and Welcome never reappears once a
/// car exists. RV.23 added the peer-prominence, restore-intent and RU-copy
/// checks. `-presentWelcome` makes the
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

    /// The same launch under a Russian UI. RV.23 fixed a copy defect that only
    /// renders in RU (the concatenated sign-in line), so the RU pass is a test,
    /// not a screenshot habit.
    private func launchRussian(_ arguments: [String]) -> XCUIApplication {
        launch(arguments + ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
    }

    // MARK: - The screen and its three paths

    func testFreshInstallShowsWelcomeWithThreeHittablePaths() {
        let app = launch(["-presentWelcome"])

        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["welcomeImportButton"].exists)
        XCTAssertTrue(app.buttons["welcomeSignInButton"].exists)
        XCTAssertTrue(app.buttons["welcomeRestoreButton"].exists)

        // The hero tagline is user-facing copy a future change could silently
        // drift. Assert the exact sentence, verbatim, so a later rewrite cannot
        // re-promise the hero without this test (and its screenshot) failing.
        XCTAssertTrue(app.staticTexts["Fuel, charging and service – one log"].waitForExistence(timeout: 5))

        // All three paths are real doors, not decoration (hard rule 15).
        XCTAssertTrue(app.buttons["welcomeAddCarButton"].isHittable)
        XCTAssertTrue(app.buttons["welcomeImportButton"].isHittable)
        XCTAssertTrue(app.buttons["welcomeSignInButton"].isHittable)
        XCTAssertTrue(app.buttons["welcomeRestoreButton"].isHittable)
    }

    // MARK: - RV.23: sign-in is a peer door, and the skip is still a peer

    /// The defect RV.23 fixed: sign-in was a 13 pt centred text link under two
    /// full-width buttons, so a user who wanted an account had to hunt for it.
    /// Existence proved nothing then and proves nothing now - this asserts the
    /// FRAMES. Sign-in must be as wide as "Add your car" and of comparable
    /// height, and "Add your car" must still be the first, full-width door: the
    /// user who never signs in has chosen correctly (hard rule 1), so the skip
    /// is never small print under a filled primary.
    func testSignInIsAPeerDoorOfComparableProminenceToAddCar() {
        let app = launch(["-presentWelcome"])

        let addCar = app.buttons["welcomeAddCarButton"]
        let signIn = app.buttons["welcomeSignInButton"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 10))
        XCTAssertTrue(signIn.exists)

        let addCarFrame = addCar.frame
        let signInFrame = signIn.frame

        XCTAssertEqual(signInFrame.width, addCarFrame.width, accuracy: 1,
                       "sign-in must be a full-width door, the same width as Add your car")
        XCTAssertGreaterThanOrEqual(
            signInFrame.height, addCarFrame.height * 0.8,
            "sign-in must be of comparable height to Add your car, not a text link")
        XCTAssertLessThanOrEqual(
            signInFrame.height, addCarFrame.height * 2.0,
            "sign-in must not dwarf Add your car either - they are peers")

        // The skip stays first and stays full width: nothing demotes it.
        XCTAssertLessThan(addCarFrame.minY, signInFrame.minY,
                          "Add your car stays the first door on the screen")
        XCTAssertEqual(addCarFrame.width, app.buttons["welcomeImportButton"].frame.width,
                       accuracy: 1)
    }

    /// The screen must now say what an account is FOR, at the decision - not
    /// argue against one before the user knows what it costs them. The old copy
    /// ("No account needed – your data stays yours") is gone; the benefit line
    /// sits inside the sign-in door itself, which is what a string check alone
    /// could not tell you.
    func testSignInDoorNamesWhatAnAccountBuys() {
        let app = launch(["-presentWelcome"])

        let signIn = app.buttons["welcomeSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(signIn.label.contains("Cloud receipt reading, sync and backup"),
                      "the benefit must live ON the door, not somewhere on the screen: \(signIn.label)")

        // The local-first promise survives, two-sided (hard rule 1).
        XCTAssertTrue(app.staticTexts[
            "Your data stays on your phone – an account adds cloud features"].exists)
        XCTAssertFalse(app.staticTexts["No account needed – your data stays yours"].exists,
                       "the row that pre-empted the decision is gone")
    }

    // MARK: - RV.23: the restore intent (docs/JOURNEYS.md J11a)

    /// The trap. The peer sign-in door is a general-purpose door, so an empty
    /// account under it is simply a new account - the wrong-provider question
    /// ("did you sign in with Google last time?") must NOT fire for someone who
    /// never claimed to be returning. The empty-restore screen is the honest
    /// destination instead.
    func testPeerSignInDoorNeverAsksTheWrongProviderQuestion() {
        let app = launch(["-presentWelcome", "-signInStubAuth"])

        XCTAssertTrue(app.buttons["welcomeSignInButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeSignInButton"].tap()

        let apple = app.buttons["signInAppleButton"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

        XCTAssertTrue(app.buttons["emptyRestoreStartFreshButton"].waitForExistence(timeout: 10),
                      "a new user over an empty account belongs on the empty-restore screen")
        XCTAssertFalse(app.staticTexts[
            "Nothing is stored under this Apple ID. Last time, did you sign in with Google?"].exists,
                       "a brand-new user must never be asked about a sign-in they never made")
    }

    /// The other half: the restore door still carries `arrivedViaRestore`, so a
    /// returning user over an empty account still gets the honest J11a question
    /// and never an empty garage that looks like data loss.
    func testRestoreDoorStillCarriesTheRestoreIntent() {
        let app = launch(["-presentWelcome", "-signInStubAuth"])

        XCTAssertTrue(app.buttons["welcomeRestoreButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeRestoreButton"].tap()

        let apple = app.buttons["signInAppleButton"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

        XCTAssertTrue(app.staticTexts[
            "Nothing is stored under this Apple ID. Last time, did you sign in with Google?"]
            .waitForExistence(timeout: 10),
                      "the restore door is the signal that carries the J11a intent")
    }

    // MARK: - RV.23: the RU copy (hard rule 10)

    /// The sign-in line used to be built by concatenation, so RU rendered
    /// "Уже пользуетесь Tankbook? Вход – гараж поедет за вами." - a noun
    /// standing where a verb belongs. Each string is one full localised phrase
    /// per language now, and this is the test that would have caught it: the
    /// bug renders acceptably in EN and badly in RU.
    func testRussianCopyIsWholePhrasesNotConcatenatedFragments() {
        let app = launchRussian(["-presentWelcome"])

        let restore = app.buttons["welcomeRestoreButton"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        XCTAssertEqual(restore.label, "Уже пользуетесь Tankbook? Восстановите свой гараж.",
                       "the returning-user line is one RU phrase, not assembled fragments")

        let signIn = app.buttons["welcomeSignInButton"]
        XCTAssertTrue(signIn.label.contains("Войти в Tankbook"),
                      "the door is a verb in RU, not the noun \"Вход\": \(signIn.label)")
        XCTAssertTrue(signIn.label.contains("Облачное распознавание чеков"),
                      "the benefit is localised too: \(signIn.label)")
        XCTAssertFalse(signIn.label.contains("Cloud receipt"),
                       "no English leaks into the RU door: \(signIn.label)")

        XCTAssertTrue(app.staticTexts[
            "Данные остаются на телефоне – аккаунт добавляет облачные возможности"].exists,
                      "the two-sided local-first promise is localised")

        // And the RU doors still fit: neither is truncated into the other's
        // space, and both stay peers at 20-30% more text.
        XCTAssertEqual(signIn.frame.width, app.buttons["welcomeAddCarButton"].frame.width,
                       accuracy: 1)
        XCTAssertTrue(restore.isHittable)
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

        // The sign-in sheet opens (the peer door, no restore intent) and
        // "Not now" returns to Welcome (SCREENMAP: SignIn -.-> Welcome).
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
    /// the path is real (the restore door -> sign-in sheet).
    func testRestoringCancelReturnsToWelcome() {
        let app = launch(["-presentWelcome", "-signInRestore", "-signInStubAuth"])
        XCTAssertTrue(app.buttons["welcomeRestoreButton"].waitForExistence(timeout: 10))
        app.buttons["welcomeRestoreButton"].tap()

        XCTAssertTrue(app.buttons["restoringOpenGarageButton"].waitForExistence(timeout: 10))
        app.buttons["restoringSignOutButton"].tap()

        XCTAssertTrue(app.buttons["welcomeAddCarButton"].waitForExistence(timeout: 10),
                      "restoring's cancel must return to Welcome, not to a dead end")
        XCTAssertFalse(app.buttons["restoringOpenGarageButton"].exists,
                       "the sheet must be gone after the cancel")
    }
}
