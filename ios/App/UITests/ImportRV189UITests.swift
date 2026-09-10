import XCTest

/// RV.189 - a Drivvo fill whose file row named its station must title itself
/// with the station, never the fuel kind ("92"). The row was titled with the
/// kind because the import dropped the station in the batch merge; this drives
/// the real wizard through confirm and asserts the rendered Log title.
@MainActor
final class ImportRV189UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    func testImportedFillTitlesItselfWithTheStationNotTheFuelKind() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportStation"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10),
                      "the preview must be on screen")
        app.buttons["importConfirmButton"].tap()

        XCTAssertTrue(app.staticTexts["Газпром"].waitForExistence(timeout: 10),
                      "the imported fill must title itself with the station the file named")
        XCTAssertFalse(app.staticTexts["92"].exists,
                       "the fuel kind must never stand in for the station the file named")
    }
}
