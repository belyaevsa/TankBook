import XCTest

/// RV.220 - the `noFuel` row's deciding action ("Import as service" / "Import as
/// expense") and "Leave out" are two intents. Before the fix both called one
/// `toggleSkipped`, so tapping the action that names keeping DROPPED the row.
/// These assert the END STATE in the Log - the commit, never the button's
/// colour - because "the label changed" is exactly the vacuous assertion the
/// defect would pass.
@MainActor
final class ImportRV220UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Signed in: the guest Home has no Log, and the assertion is on the Log
    /// row the commit writes (RV.88's suite signs in for the same reason).
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + arguments
        app.launch()
        return app
    }

    private func russian(_ arguments: [String]) -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] + arguments)
    }

    /// Tap the keep action, finish the wizard, and assert the service landed.
    private func finishImport(_ app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))
        app.buttons["importReviewDoneButton"].tap()
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))
        app.buttons["importConfirmButton"].tap()
    }

    func testImportAsServiceLandsInTheLog() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportService"])
        XCTAssertTrue(app.staticTexts["Import as service"].waitForExistence(timeout: 10),
                      "the non-fuel row offers the import-as-service action")
        app.staticTexts["Import as service"].tap()

        finishImport(app)
        XCTAssertTrue(app.staticTexts["Oil change"].waitForExistence(timeout: 10),
                      "tapping 'Import as service' must COMMIT the service, not drop it (hard rule 8)")
    }

    func testLeaveOutKeepsTheServiceOutOfTheLog() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportService"])
        XCTAssertTrue(app.staticTexts["Leave out"].waitForExistence(timeout: 10))
        app.staticTexts["Leave out"].tap()

        finishImport(app)
        XCTAssertFalse(app.staticTexts["Oil change"].waitForExistence(timeout: 5),
                       "a left-out service must not be committed")
    }

    func testImportAsServiceLandsInTheLogInRussian() {
        let app = russian(["-presentScreen", "importWizard",
                           "-importStubFormats", "one", "-seedImportService"])
        XCTAssertTrue(app.staticTexts["Импортировать как сервис"].waitForExistence(timeout: 10))
        app.staticTexts["Импортировать как сервис"].tap()

        finishImport(app)
        XCTAssertTrue(app.staticTexts["Oil change"].waitForExistence(timeout: 10),
                      "the RU 'Импортировать как сервис' must commit the service, not drop it")
    }

    func testLeaveOutKeepsTheServiceOutOfTheLogInRussian() {
        let app = russian(["-presentScreen", "importWizard",
                           "-importStubFormats", "one", "-seedImportService"])
        XCTAssertTrue(app.staticTexts["Пропустить"].waitForExistence(timeout: 10))
        app.staticTexts["Пропустить"].tap()

        finishImport(app)
        XCTAssertFalse(app.staticTexts["Oil change"].waitForExistence(timeout: 5),
                       "a left-out service must not be committed in the RU flow either")
    }
}
