import XCTest

/// PJ.44 - cancel leaves nothing behind on EVERY exit (F6a): a stored parse is
/// deleted when the user backs out to the source step and closes the wizard -
/// the path that had no Cancel handler - through the wizard's `onDisappear`,
/// which also covers a presenter closing it. The wizard is a pushed screen
/// with its bar hidden, so there is no swipe exit to test. The import stub
/// counts the DELETE and Home renders the `importParseDeleted` marker once one
/// landed.
@MainActor
final class ImportExitDeleteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", "-observeImportDelete",
                               "-presentScreen", "importWizard", "-importStubFormats", "one",
                               "-seedImportPreview"]
        app.launch()
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10),
                      "the seeded parse opens on the preview")
        return app
    }

    private func marker(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["importParseDeleted"]
    }

    func testBackToSourceThenCloseDeletesTheStoredParse() {
        let app = launchPreview()
        XCTAssertFalse(marker(app).exists, "nothing is deleted while the parse is being reviewed")

        app.buttons["importHeaderBack"].tap()
        let close = app.buttons["importSourceClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Back lands on the source step")
        close.tap()

        XCTAssertTrue(marker(app).waitForExistence(timeout: 10),
                      "closing the wizard from the source step must DELETE the parse it still held")
    }
}
