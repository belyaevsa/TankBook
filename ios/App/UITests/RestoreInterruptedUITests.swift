import XCTest

/// PJ.39 - the interrupted-restore row (docs/ERRORS.md -> Restoring, "Pull
/// interrupted"; F7): the connection dropped mid-pull, the notice names the
/// next step, what landed so far is shown, and both doors are on it - open the
/// partial garage, retry now. With nothing landed, the garage door is absent
/// (there is no partial garage) and the retry remains.
@MainActor
final class RestoreInterruptedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    func testTheInterruptedRowNamesBothNextStepsAndWhatLanded() {
        let app = launch(["-presentScreen", "signIn", "-signInRestoreInterrupted"])

        let message = app.staticTexts["restoreInterruptedMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertEqual(message.label, "Connection dropped – restore continues when you're back online.")

        XCTAssertTrue(app.descendants(matching: .any)["restoreInterruptedLandedCard"].exists,
                      "what landed before the drop is shown in numbers")
        let openGarage = app.buttons["restoreInterruptedOpenGarageButton"]
        XCTAssertTrue(openGarage.exists && openGarage.isHittable, "the partial garage is one tap away")
        XCTAssertTrue(app.buttons["restoreInterruptedRetryButton"].isHittable, "retry is one tap away")

        // The partial garage opens: the sheet closes onto the app.
        openGarage.tap()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5))
    }

    func testNothingLandedOffersRetryButNoPartialGarage() {
        let app = launch(["-presentScreen", "signIn", "-signInRestoreInterruptedEmpty"])
        XCTAssertTrue(app.staticTexts["restoreInterruptedMessage"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["restoreInterruptedOpenGarageButton"].exists,
                       "no page landed - there is no partial garage to open")
        XCTAssertTrue(app.buttons["restoreInterruptedRetryButton"].isHittable)
    }

    func testTheInterruptedRowIsWholeRussianCopy() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "signIn", "-signInRestoreInterrupted"])
        let message = app.staticTexts["restoreInterruptedMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertEqual(message.label, "Связь прервалась – восстановление продолжится, когда вы снова будете в сети.")
        XCTAssertTrue(app.buttons["Повторить сейчас"].exists)
        XCTAssertTrue(app.buttons["Открыть гараж (частично, продолжает заполняться)"].exists)
    }
}
