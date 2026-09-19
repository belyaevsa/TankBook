import XCTest

/// The S5 "came back" card on Home (docs/SYNC.md S5; docs/ERRORS.md -> Home,
/// "Archived car returned via sync"): real data through the sync resurrect,
/// both answers working, EN and RU phrasing. The Garage's copy and "Delete
/// again" are in `GarageUITests`.
@MainActor
final class HomeReturnedCarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String],
                        language: [String] = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + language + args
        app.launch()
        return app
    }

    /// The S5 card is REAL: the seed deletes a car and lets a pulled entry
    /// resurrect it through the sync path, so the card reads the resurrect's
    /// own notice - its name and count - and no launch argument can paint it.
    /// Keep consumes the notice and leaves the car archived.
    func testTheReturnedCarCardReadsItsNoticeAndKeepClearsIt() {
        let app = launch(args: ["-seedHomeArchivedReturned"])

        // Home and Garage each mount the card (the tab roots stay mounted),
        // so the query is by first match; both copies answer the same row.
        let message = app.staticTexts["vehicleReturnMessage"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), "the resurrect's notice renders the card")
        XCTAssertEqual(message.label, "Saab 9-3 came back with 1 new entry – stays archived.")

        app.buttons["vehicleReturnKeep"].firstMatch.tap()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5), "Keep consumes the notice")
        // The card asked once: a relaunch over the same database shows no card.
        app.terminate()
        app.launchArguments = ["-seedSettingsSignedIn"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(message.exists, "an answered notice never comes back")
    }

    func testTheReturnedCarCardReadsRussianPlurals() {
        let app = launch(args: ["-seedHomeArchivedReturned"],
                         language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        let message = app.staticTexts["vehicleReturnMessage"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertEqual(message.label, "«Saab 9-3» вернулся с 1 новой записью – остаётся в архиве.")
        XCTAssertTrue(app.buttons["Удалить снова"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Оставить"].firstMatch.exists)
    }
}
