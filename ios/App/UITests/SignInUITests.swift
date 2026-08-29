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

    /// The REAL path (PJ.3): the Welcome root's third path carries the restore
    /// intent (`arrivedViaRestore: true`), so an empty stub account under it
    /// asks the honest question - no `-signInWrongProvider` fixture remains.
    func testWrongProviderShowsHonestQuestionAndProviderSwitchIsOneTap() {
        let app = launch(["-presentWelcome", "-signInStubAuth"])

        // A fresh install shows Welcome; the third path is the restore door.
        XCTAssertTrue(app.staticTexts["Tankbook"].waitForExistence(timeout: 10))
        let signIn = app.buttons["welcomeSignInButton"]
        XCTAssertTrue(signIn.isHittable)
        signIn.tap()

        let apple = app.buttons["signInAppleButton"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

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

    /// A local car plus a restore in progress: signing out of the account must
    /// clear only the session, never the local log (J11a's reverse guard, hard
    /// rule 1). The guest Home renders because the session is gone (PJ.3) and
    /// the local garage card survives.
    func testSignOutEscapeLeavesTheLocalAppIntact() {
        let app = launch(["-seedHomeEmptyVehicle", "-presentScreen", "signIn", "-signInRestore"])

        XCTAssertTrue(app.buttons["restoringSignOutButton"].waitForExistence(timeout: 10))
        app.buttons["restoringSignOutButton"].tap()

        // Back on the working app, and the seeded local car is still there -
        // signing out cleared only the session, never the local log. The guest
        // garage card names the car.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 5),
                      "the local garage must survive the sign-out escape")
        XCTAssertFalse(app.staticTexts["Nothing is stored under this Apple ID. Last time, did you sign in with Google?"].exists)
    }

    // MARK: - Nothing is sync-gated (hard rule 1)

    func testSignInDeclinedLeavesLogTrendsGarageWorkingAndAnEntrySaves() {
        // A deterministic guest launch: a leftover session from an earlier
        // test would flip Home into the signed-in layout and hide the guest
        // door this test must use (guest chrome is real state since PJ.3).
        let app = launch(["-clearSessionAtLaunch", "-seedVehicleForUITests", "-presentScreen", "signIn"])

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

        // An entry saves: back to Log, type a fill-up, save. The declined
        // sign-in leaves the app a guest, so the guest Home's own "Type it"
        // door is the peer entry path (hard rule 15).
        app.buttons["tabbar.log"].tap()
        XCTAssertTrue(app.buttons["homeGuestCaptureButton"].waitForExistence(timeout: 10))
        app.buttons["homeGuestCaptureButton"].tap()

        focusField(app, "manualFillUpTotalField").typeText("71.02")
        focusField(app, "manualFillUpLitersField").typeText("42.30")

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "two of three typed must enable save with no account")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
    }

    // MARK: - PJ.13 the first push after sign-in (docs/JOURNEYS.md J11a)

    /// Signing in with a populated local log uploads it and finishes the flow:
    /// the sheet closes to a signed-in Settings card, and the wrong-provider
    /// question never appears - a local log is never routed there (J11a's
    /// reverse guard) and the upload branch must never push into an unaccepted
    /// account. The push runs through the sign-in stub transport.
    func testSignInWithLocalLogUploadsAndCompletesTheFlow() {
        let app = launch(["-presentScreen", "settings", "-seedSettingsLocalLog",
                          "-signInStubAuth", "-signInSyncStub"])

        let signIn = app.buttons["settingsSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        signIn.tap()

        let apple = app.buttons["signInAppleButton"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

        // The upload branch completes the flow - the wrong-provider question
        // must not appear (a populated local log always uploads), and the card
        // is back signed in.
        let wrongProviderQuestion = app.staticTexts[
            "Nothing is stored under this Apple ID. Last time, did you sign in with Google?"]
        XCTAssertFalse(wrongProviderQuestion.waitForExistence(timeout: 5),
                       "a populated local log must never reach the wrong-provider question")
        XCTAssertTrue(app.staticTexts["settingsSyncStatus"].waitForExistence(timeout: 15),
                      "the flow must finish with a signed-in Settings card")
        XCTAssertTrue(app.staticTexts["settingsSignedInConfirmation"].waitForExistence(timeout: 5),
                      "the J11a confirmation line follows the first push")
    }

    // MARK: - The restoring screen's verification stats (docs/JOURNEYS.md J11)

    /// The Restoring screen shows the verification stats - numbers, not a
    /// checkmark - composed as full localised phrases (RU plural rules for the
    /// count, never concatenation).
    func testRestoringScreenShowsVerificationStats() {
        let app = launch(["-presentScreen", "signIn", "-signInRestore"])

        XCTAssertTrue(app.buttons["restoringOpenGarageButton"].waitForExistence(timeout: 10))

        // The two full phrases: cars and entries, each one localised string with
        // the plural count (RU plural rules), never concatenation.
        let cars = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "2 cars – Volvo V60, ID.4"))
        XCTAssertTrue(cars.firstMatch.exists, "the cars line must name the count and the cars")

        let entries = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "428 entries"))
        XCTAssertTrue(entries.firstMatch.exists, "the entries line must show the literal entry count")

        // The escape and the finish affordance are both present.
        XCTAssertTrue(app.buttons["restoringSignOutButton"].exists)
    }

    // MARK: - The empty-restore recovery entry point (docs/JOURNEYS.md F7)
    /// An empty restore must reach the recovery entry point BEFORE any "add a
    /// car" affordance is usable - the whole point is preventing the user from
    /// typing first and creating a merge conflict when the backup reappears.
    /// Driven through the REAL flow (a stub sign-in from Settings, which
    /// carries no restore intent): the empty account is accepted, the session
    /// sticks, and only then does add-a-car become reachable.
    func testEmptyRestoreShowsRecoveryBeforeAddCarIsUsable() {
        let app = launch(["-presentScreen", "signIn", "-signInStubAuth"])

        // Sign in: an empty account with no restore intent lands on the
        // recovery entry point (F7), never on a bare empty garage.
        XCTAssertTrue(app.buttons["signInAppleButton"].waitForExistence(timeout: 10))
        app.buttons["signInAppleButton"].tap()
        XCTAssertTrue(app.staticTexts["emptyRestoreRecoveryPrompt"].waitForExistence(timeout: 10),
                      "an empty restore must show the 'Expecting your data?' recovery entry point")
        XCTAssertTrue(app.staticTexts["Expecting your data?"].exists)
        XCTAssertTrue(app.buttons["emptyRestoreStartFreshButton"].exists)

        // ...BEFORE the add-a-car affordance is usable: it sits behind the sheet,
        // so it must not be hittable while the recovery screen is up.
        XCTAssertFalse(app.buttons["homeAddFirstCarButton"].isHittable,
                       "the add-a-car affordance must not be usable before the empty-restore decision")

        // "Start fresh" is the explicit acceptance of the empty garage - only
        // then does add-a-car become reachable (and only because the accepted
        // account left a session: a no-session user is the guest Home, not the
        // signed-in empty garage, since PJ.3).
        app.buttons["emptyRestoreStartFreshButton"].tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeAddFirstCarButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeAddFirstCarButton"].isHittable,
                      "add-a-car becomes usable only after the user accepts the empty garage")
    }

    // MARK: - The backend-down state (docs/JOURNEYS.md F7)

    /// A down backend says exactly that, with its next step and a reachable
    /// import path - never a generic "something went wrong".
    func testBackendDownShowsF7CopyAndReachableImportPath() {
        let app = launch(["-presentScreen", "signIn", "-signInRestoreUnreachable"])

        // The F7 copy, verbatim (docs/ERRORS.md -> Restoring), not a generic error.
        // Asserted by identifier + label: the literal exceeds XCUITest's 128-char
        // identifier ceiling, so query by the element's id and check its text.
        let message = app.staticTexts["restoreUnreachableMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        let f7Copy = "Sync service unreachable – your data is safe on the server. "
            + "You can import an export file, or it will all arrive when the service is back."
        XCTAssertEqual(message.label, f7Copy)

        // The import path is reachable from it, and the retry is one tap.
        XCTAssertTrue(app.buttons["restoreUnreachableImportRow"].exists)
        XCTAssertTrue(app.buttons["restoreUnreachableImportRow"].isHittable)
        XCTAssertTrue(app.buttons["restoreUnreachableRetryButton"].exists)

        // No add-a-car path is offered while the backend is down either.
        XCTAssertFalse(app.buttons["homeAddFirstCarButton"].isHittable)
    }
}
