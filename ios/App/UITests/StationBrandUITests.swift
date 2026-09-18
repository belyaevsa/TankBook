import XCTest

/// RV.115 + RV.180 - the station brand vocabulary on the device. An imported
/// fill whose station column is a receipt's full printed line shows the BRAND
/// the matcher chose - on the Log row and beside the site in the Garage - and
/// the user can change it, in the Garage and from the entry's station row,
/// with the pick surviving a relaunch (hard rule 13).
@MainActor
final class StationBrandUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String], russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-freezeSyncState"]
            + (russian ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] : []) + arguments
        app.launch()
        return app
    }

    /// Garage -> Stations, scrolling only if the door sits below the fold.
    private func openStations(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        let link = app.buttons["garageStationsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the Garage must always offer the Stations door")
        if !link.isHittable { app.swipeUp() }
        link.tap()
    }

    /// Picks a brand in the open picker through its search field: the list
    /// is lazy, so a chain far down the device-ordered vocabulary is not in
    /// the accessibility tree until the search narrows it.
    private func pickBrand(_ app: XCUIApplication, id: String, query: String) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the picker has a search field")
        search.tap()
        search.typeText(query)
        let row = app.buttons[id]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the picker lists the vocabulary: \(id)")
        row.tap()
    }

    private func importTheBrandFile(_ app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10),
                      "the seeded parse opens on the review")
        app.buttons["importReviewDoneButton"].tap()
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))
        app.buttons["importConfirmButton"].tap()
    }

    /// The matcher's pick shows on the Log row, on the Garage's station row and
    /// on the station's Brand card; changing it in the Garage changes what the
    /// Log row says, and the pick survives a relaunch.
    private func importedFillShowsItsBrandAndTheUserChangesIt(russian: Bool) {
        let app = launch(["-seedSettingsSignedIn", "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportBrand"], russian: russian)
        importTheBrandFile(app)

        XCTAssertTrue(app.staticTexts["Gazpromneft"].waitForExistence(timeout: 10),
                      "the imported fill titles itself with the brand the matcher chose")
        XCTAssertFalse(app.staticTexts["ООО \"Газпромнефть-Центр\" АЗС 12089"].exists,
                       "the Log row shows the chain, not the site's printed line")

        // Garage -> Stations: the site's line beside its brand.
        openStations(app)
        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Gazpromneft"), "the station row names the brand: \(row.label)")
        row.tap()

        let brandValue = app.staticTexts["stationSettingsBrandValue"]
        XCTAssertTrue(brandValue.waitForExistence(timeout: 10))
        XCTAssertEqual(brandValue.label, "Gazpromneft")

        // Change it: the picker lists the vocabulary; Lukoil is one tap.
        app.buttons["stationSettingsBrandButton"].tap()
        pickBrand(app, id: "stationBrand_lukoil", query: "Luk")
        XCTAssertEqual(brandValue.label, "Lukoil", "the pick is written and shown at once")

        // And "no brand" is a first-class choice, then back to Lukoil.
        app.buttons["stationSettingsBrandButton"].tap()
        XCTAssertTrue(app.buttons["stationBrandNone"].waitForExistence(timeout: 10))
        app.buttons["stationBrandNone"].tap()
        XCTAssertEqual(brandValue.label, russian ? "Без бренда" : "No brand")
        app.buttons["stationSettingsBrandButton"].tap()
        pickBrand(app, id: "stationBrand_lukoil", query: "Лукойл")
        XCTAssertEqual(brandValue.label, "Lukoil", "an alias in another script finds the same chain")
    }

    func testAnImportedFillShowsItsBrandAndTheUserChangesItInTheGarage() {
        importedFillShowsItsBrandAndTheUserChangesIt(russian: false)
    }

    func testAnImportedFillShowsItsBrandAndTheUserChangesItInTheGarageInRussian() {
        importedFillShowsItsBrandAndTheUserChangesIt(russian: true)
    }

    /// The Log row follows the user's pick, and the pick survives a relaunch:
    /// the brand is theirs, and no launch-time pack refresh rewrites it.
    func testTheUsersBrandPickTitlesTheLogRowAndSurvivesARelaunch() {
        let app = launch(["-seedSettingsSignedIn", "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportBrand"])
        importTheBrandFile(app)
        XCTAssertTrue(app.staticTexts["Gazpromneft"].waitForExistence(timeout: 10))

        openStations(app)
        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let brandButton = app.buttons["stationSettingsBrandButton"]
        XCTAssertTrue(brandButton.waitForExistence(timeout: 10))
        brandButton.tap()
        pickBrand(app, id: "stationBrand_lukoil", query: "Luk")
        XCTAssertEqual(app.staticTexts["stationSettingsBrandValue"].label, "Lukoil")

        // No `-homeResetDatabase`: the same database, a fresh process.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-seedSettingsSignedIn", "-freezeSyncState"]
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["Lukoil"].waitForExistence(timeout: 10),
                      "the Log row titles itself with the user's own brand after a relaunch")
        XCTAssertFalse(relaunched.staticTexts["Gazpromneft"].exists,
                       "the matcher's original pick must not come back")
    }

    /// RV.180: editable at the Confirm sheet too. The scanned station's brand
    /// sits under the station on the row, and the menu's "Change brand" opens
    /// the same picker.
    func testTheConfirmSheetShowsTheScannedStationsBrandAndCanChangeIt() {
        let app = launch(["-seedVehicleForUITests", "-presentScreen", "confirmManual", "-seedConfirmPrefillStation"])
        let field = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the Confirm sheet must be on screen")

        let caption = app.staticTexts["manualFillUpStationBrand"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10), "the scanned station's brand shows on the row")
        XCTAssertEqual(caption.label, "Circle K")

        app.buttons["manualFillUpStationButton"].tap()
        let change = app.buttons["manualFillUpChangeBrandMenuItem"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "the station menu offers the brand change")
        change.tap()
        pickBrand(app, id: "stationBrand_neste", query: "Nes")
        XCTAssertEqual(caption.label, "Neste", "the pick shows on the row at once")
    }
}
