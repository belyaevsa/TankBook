import XCTest

// MARK: - PJ.19 the station suggestion (docs/JOURNEYS.md -> J4)

/// PJ.19: the Confirm sheet pre-selects the ranked station and the pick stays
/// changeable. The location is INJECTED (`-seedStationLocation`), never the
/// simulator's real fix, so the test is deterministic; the stations come from
/// `-seedStationSuggestion` (a favourite at the injected coordinate plus a
/// plain station ~40 m away). Hard rule 13: a suggestion is a default input,
/// and its absence is a non-event - no stations means no suggestion label at
/// all, exactly the pre-PJ.19 row.
@MainActor
extension ConfirmManualUITests {

    /// Launches with two seeded stations and the device position set to the
    /// favourite's own coordinate: rung 1 (nearest favourite within 300 m) must
    /// win - the suggestion is WHICH station, never merely that one appears.
    private func launchWithStationSuggestion() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedStationSuggestion",
                               "-seedStationLocation", "59.4378,24.7536"]
        app.launch()
        return app
    }

    func testSuggestedStationIsPreSelectedAndChangeable() {
        let app = launchWithStationSuggestion()
        openManualForm(app)

        // The row is the menu with the favourite pre-selected as its label -
        // NOT the plain station that is also within range.
        let stationButton = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(stationButton.waitForExistence(timeout: 10),
                      "seeded stations + a location must make the row a menu")
        XCTAssertTrue(stationButton.label.contains("Prima Auto"),
                      "rung 1 must pre-select the nearest favourite, got '\(stationButton.label)'")
        XCTAssertFalse(stationButton.label.contains("Circle K"),
                       "the non-favourite in range must not win the suggestion")

        // Still changeable (hard rule 13): the menu lists every station and the
        // pick lands.
        stationButton.tap()
        let other = app.buttons["Circle K Sadama"]
        XCTAssertTrue(other.waitForExistence(timeout: 5),
                      "the menu must list the other station")
        other.tap()
        let changed = NSPredicate(format: "label CONTAINS %@", "Circle K Sadama")
        expectation(for: changed, evaluatedWith: stationButton)
        waitForExpectations(timeout: 5)
    }

    func testNoStationsShowsNoSuggestionAndTheHonestPlaceholder() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedStationLocation", "59.4378,24.7536"]
        app.launch()
        openManualForm(app)

        // No stations on file: there is no suggestion label and no menu at all -
        // the row is the honest "Not set" placeholder (docs/ERRORS.md -> Confirm).
        let notSet = app.staticTexts["manualFillUpStationRow"]
        XCTAssertTrue(notSet.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["manualFillUpStationButton"].exists,
                       "with no stations there is nothing to suggest and nothing to open")
        XCTAssertFalse(app.staticTexts["Prima Auto"].exists)
        XCTAssertFalse(app.staticTexts["Circle K Sadama"].exists)
    }
}
