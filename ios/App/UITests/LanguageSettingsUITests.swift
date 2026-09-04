import XCTest

/// RV.24: the Language row is a real picker, not the inert placeholder it used
/// to be. The row must be hittable (an existence check would pass against the
/// bug), it opens a picker listing the app's real localizations plus a "System
/// default" way back to following the system, choosing one writes the
/// preference and shows the restart prompt, and the row's displayed value
/// changes. The RU pass asserts the prompt's Russian copy.
@MainActor
final class LanguageSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // -languageReset clears any stored AppleLanguages preference so the test
        // starts from "follow the system" (UserDefaults survive
        // -homeResetDatabase, which wipes only the database).
        app.launchArguments = ["-homeResetDatabase", "-languageReset"] + arguments
        app.launch()
        return app
    }

    private func launchSettingsEN() -> XCUIApplication {
        // -AppleLanguages forces English so a prior test's persisted choice (the
        // app renders in the language it launched with, decided before any
        // reset can run) cannot leak into this run.
        launch(["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-presentScreen", "settings", "-seedSettingsGuest"])
    }

    private func launchSettingsRU() -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                "-presentScreen", "settings", "-seedSettingsGuest"])
    }

    func testLanguageRowOpensPickerListingRealLocalizations() {
        let app = launchSettingsEN()
        let row = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the language row exists")
        XCTAssertTrue(row.isHittable, "the language row is hittable - it must not be inert")
        row.tap()

        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 10),
                      "the row opens the language picker")
        XCTAssertTrue(app.buttons["languageOption-system"].exists,
                      "the picker offers a way back to follow the system")
        XCTAssertTrue(app.buttons["languageOption-en"].exists,
                      "the picker lists the app's English localization")
        XCTAssertTrue(app.buttons["languageOption-ru"].exists,
                      "the picker lists the app's Russian localization")
    }

    func testChoosingALanguageShowsThePromptAndChangesTheRow() {
        let app = launchSettingsEN()
        let row = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let russian = app.buttons["languageOption-ru"]
        XCTAssertTrue(russian.waitForExistence(timeout: 10))
        russian.tap()

        let prompt = app.staticTexts["settingsLanguagePrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5),
                      "choosing a language shows the restart prompt")
        XCTAssertEqual(prompt.label,
                       "Language changes the next time you open Tankbook",
                       "the prompt names its next step, never a bare 'restart required'")

        app.buttons["settingsLanguageDoneButton"].tap()

        let value = app.staticTexts["settingsLanguageValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "Русский",
                       "the row now shows the chosen language; got '\(value.label)'")
    }

    func testRestartNoticeSurvivesDismissingThePicker() {
        let app = launchSettingsEN()
        let row = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let russian = app.buttons["languageOption-ru"]
        XCTAssertTrue(russian.waitForExistence(timeout: 10))
        russian.tap()

        app.buttons["settingsLanguageDoneButton"].tap()

        // RV.42, the bug: the notice used to live only in the picker's @State
        // and died with the sheet, so Settings showed the new value with nothing
        // saying the app is still running the old language. It must be STILL
        // visible on the row after the picker is dismissed - and it must be the
        // real copy, not merely "some element exists".
        let notice = app.staticTexts["settingsLanguagePendingNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "the restart notice survives dismissing the picker (hard rule 7)")
        XCTAssertEqual(notice.label,
                       "Language changes the next time you open Tankbook",
                       "the row notice names its next step")
    }

    func testSystemDefaultReturnsToFollowingTheSystem() {
        let app = launchSettingsEN()
        let row = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        app.buttons["languageOption-ru"].tap()
        app.buttons["languageOption-system"].tap()

        XCTAssertTrue(app.staticTexts["settingsLanguagePrompt"].exists,
                      "returning to the system also prompts the restart")
        app.buttons["settingsLanguageDoneButton"].tap()

        let value = app.staticTexts["settingsLanguageValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "English",
                       "the row follows the system again (system is English); got '\(value.label)'")
    }

    func testRussianPromptNamesItsNextStep() {
        let app = launchSettingsRU()
        let row = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let english = app.buttons["languageOption-en"]
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        english.tap()

        let prompt = app.staticTexts["settingsLanguagePrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5),
                      "the restart prompt renders in Russian")
        XCTAssertEqual(prompt.label,
                       "Язык изменится при следующем открытии Tankbook",
                       "the RU prompt names its next step")
    }
}
