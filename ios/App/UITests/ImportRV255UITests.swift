import XCTest

/// RV.255 - the import selects nothing, so a user who already has a car and
/// imports into a NEW one lands back on the OLD car and reads the moment as
/// "my import disappeared". The commit must select the car it created; an
/// import into an EXISTING car must leave the selection where the user put it.
///
/// The assertion is the returned Home's switcher label and a log row WITHOUT a
/// switcher tap - not the toast, and not a fresh install where the
/// first-non-archived fallback would pick the new car anyway.
@MainActor
final class ImportRV255UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Signed in: the switcher button is the signed-in Home's header, and the
    /// assertion is what that header names on the return.
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + arguments
        app.launch()
        return app
    }

    private func finishImport(_ app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10),
                      "the seeded flow must reach the preview gate")
        // RV.263: both seeds are files with no currency column, so the currency
        // card gates the commit until answered (F6: never import a guess). The
        // answer is irrelevant to this row's selection assertions.
        let picker = app.buttons["importCurrencyPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "the currency card must render for a file with no currency column")
        picker.tap()
        let rub = app.buttons["importCurrencyOption-RUB"]
        XCTAssertTrue(rub.waitForExistence(timeout: 5), "the RUB option never appeared")
        rub.tap()
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "answering the currency question must enable confirm")
        app.buttons["importConfirmButton"].tap()
    }

    /// The defect: an existing car is in the garage and the import creates a new
    /// one. Home must land on the created car - its name in the switcher and one
    /// of its rows in the log - without a switcher tap.
    func testImportIntoNewCarSelectsItOnReturnHome() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportNewCarExisting"])
        finishImport(app)

        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10),
                      "the wizard closes and Home returns")
        XCTAssertTrue(switcher.label.contains("Imported car"),
                      "Home must land on the car the import created, was '\(switcher.label)'")
        XCTAssertTrue(app.buttons["logEntryButton"].firstMatch.waitForExistence(timeout: 8),
                      "the imported car's log rows must be on screen without a switcher tap")
    }

    /// The counterpart: importing into the car the user chose must not yank them
    /// to another one. The switcher stays on the existing car.
    func testImportIntoExistingCarLeavesTheSwitcherOnIt() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCurrency"])
        finishImport(app)

        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10),
                      "the wizard closes and Home returns")
        XCTAssertTrue(switcher.label.contains("Volvo V60"),
                      "an import into the existing car must not move the selection, was '\(switcher.label)'")
    }
}
