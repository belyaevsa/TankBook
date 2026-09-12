import XCTest

/// RV.260 - the local restore-from-backup door (docs/JOURNEYS.md J11, F7 source
/// 3). The user-held fallback: an archive Tankbook itself exported, read back
/// with no account and no network. The failure screens' "Import a file you
/// exported yourself" row must open THIS door, not the third-party wizard that
/// parses My Fuel Manager / Drivvo and rejects a Tankbook backup.
@MainActor
final class RestoreFromBackupUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    /// The empty-restore screen's primary row imports a REAL archive (built by
    /// `RestoreBackupTestSeed` through `ExportBuilder`, never hand-made) and the
    /// car and its entry land on Home. The third-party source picker must never
    /// appear - the mutation (point the row back at `Route.importWizard`) fails
    /// here on `importSourceTitle`.
    func testEmptyRestoreBackupRowRestoresArchiveToHome() {
        let app = launch(["-presentScreen", "signIn", "-signInRestoreEmpty", "-seedRestoreBackup"])

        // Both doors: the local backup, and the third-party wizard beside it.
        let backup = app.buttons["emptyRestoreBackupRow"]
        XCTAssertTrue(backup.waitForExistence(timeout: 10), "the backup row must render")
        XCTAssertTrue(app.buttons["emptyRestoreImportRow"].exists,
                      "the third-party wizard keeps its own door beside the backup door")

        backup.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 15),
                      "a successful restore closes the sign-in sheet and lands on Home")
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 10),
                      "the archive's car must appear on Home")
        XCTAssertEqual(app.staticTexts.matching(identifier: "homeEntryAmount").count, 1,
                       "the archive's entry must appear on Home")
        XCTAssertFalse(app.staticTexts["importSourceTitle"].exists,
                       "the backup row must never open the third-party source picker")
    }

    /// The same walk in Russian - the overflow check for the new screen and the
    /// two-door recovery card.
    func testEmptyRestoreBackupRowRestoresArchiveToHomeInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "signIn", "-signInRestoreEmpty", "-seedRestoreBackup"])

        let backup = app.buttons["emptyRestoreBackupRow"]
        XCTAssertTrue(backup.waitForExistence(timeout: 10))
        backup.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "homeEntryAmount").count, 1)
        XCTAssertFalse(app.staticTexts["importSourceTitle"].exists)
    }

    /// The backend-down screen's row opens the SAME local door - the archive is
    /// read with no connection, so a down sync service cannot block it.
    func testUnreachableBackupRowOpensTheLocalDoor() {
        let app = launch(["-presentScreen", "signIn", "-signInRestoreUnreachable"])

        let backup = app.buttons["restoreUnreachableBackupRow"]
        XCTAssertTrue(backup.waitForExistence(timeout: 10))
        backup.tap()

        XCTAssertTrue(app.staticTexts["restoreBackupTitle"].waitForExistence(timeout: 10),
                      "the local backup screen must open, not the third-party picker")
        XCTAssertTrue(app.buttons["restoreBackupChooseButton"].exists)
        XCTAssertFalse(app.staticTexts["importSourceTitle"].exists)
    }

    /// Settings carries the door beside Export: the pair reads as one
    /// capability - write it out, read it back.
    func testSettingsRestoreBackupRowOpensTheLocalDoor() {
        let app = launch(["-presentScreen", "settings", "-seedSettingsSignedIn"])

        let row = app.buttons["settingsRestoreBackupRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "Restore from backup must sit beside Export in Settings")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        XCTAssertTrue(app.staticTexts["restoreBackupTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["importSourceTitle"].exists)
    }
}
