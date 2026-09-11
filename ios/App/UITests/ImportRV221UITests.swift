import XCTest

/// RV.221 - F6b promises the review row renders "date, station, litres, price,
/// total, odometer, note". The station was rendered nowhere, so a wrong mapping
/// surfaced only after the commit, in the Log. The seeded fill names a long
/// station (43 characters) and needs a look, so its name must appear on the
/// review row in both locales - the RU case is where a truncating cell hides it.
@MainActor
final class ImportRV221UITests: XCTestCase {

    private static let stationName = "Газпромнефть на Ленинградском проспекте, 63"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func assertStationRenders(_ app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[Self.stationName].waitForExistence(timeout: 5),
                      "the review row must render the file's station name, not only its id")
    }

    func testReviewRowRendersTheStationName() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportStationReview"])
        assertStationRenders(app)
    }

    func testReviewRowRendersTheStationNameInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportStationReview"])
        assertStationRenders(app)
    }
}
