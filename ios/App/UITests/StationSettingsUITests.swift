import XCTest

/// RV.150 - the Garage per-station settings surface. The product decision says
/// the coordinate a fill-up save captures silently must be visible, editable
/// and clearable where per-station settings live - the Garage (property 1:
/// "silently" is bounded to the capture moment, never invisible). These tests
/// drive the Garage door -> Stations list -> station settings path, assert the
/// captured location is shown, and prove the removal control works. The
/// location arrives through `-seedStationSettings`, whose station is already
/// stamped (a location, a lastUsedAt and bought defaults) - the state a save
/// produces.
@MainActor
final class StationSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func openGarage(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
    }

    /// The Garage -> Stations door. Scrolls only if the row sits below the fold
    /// (a short garage fits it on screen; a car grid may not).
    private func openStations(_ app: XCUIApplication) {
        let link = app.buttons["garageStationsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "the Garage must always offer the Stations door")
        if !link.isHittable {
            app.swipeUp()
        }
        link.tap()
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 5))
    }

    func testStationsReachableFromGarageShowACapturedLocationAndCanClearIt() {
        let app = launch(["-seedStationSettings"])
        openGarage(app)
        openStations(app)

        // The seeded stamped station is listed.
        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the stamped station must be listed")
        XCTAssertTrue(row.label.contains("Prima Auto"),
                      "the row must name the station, got '\(row.label)'")
        XCTAssertTrue(row.label.contains("Location saved"),
                      "a station with a captured location must say so, got '\(row.label)'")
        row.tap()

        // The per-station settings show the captured coordinate.
        XCTAssertTrue(app.navigationBars["Station"].waitForExistence(timeout: 5))
        let value = app.staticTexts["stationSettingsLocationValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "59.4378, 24.7536",
                       "the captured location must be visible, got '\(value.label)'")

        // And it is clearable in place (property 1). No confirmation: clearing
        // is reversible - a later save at this station with a fix re-adopts it.
        let remove = app.buttons["stationSettingsRemoveLocation"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5),
                      "a captured location must offer the removal control")
        remove.tap()
        let notSet = app.staticTexts["stationSettingsLocationValue"]
        XCTAssertTrue(notSet.waitForExistence(timeout: 5))
        XCTAssertEqual(notSet.label, "Not set",
                       "after removal the row must say Not set, got '\(notSet.label)'")
        XCTAssertFalse(app.buttons["stationSettingsRemoveLocation"].exists,
                       "with no location there is nothing left to remove")
    }

    func testTheStationsDoorIsAlwaysPresentAndLeadsToAnHonestEmptyState() {
        let app = launch([])
        openGarage(app)

        // No cars, no stations: the Stations door is still present (it is a
        // calm management door, like Home's reminders row) and its list says
        // honestly what a station is for rather than drawing a blank.
        openStations(app)
        XCTAssertTrue(app.staticTexts["stationsEmptyState"].waitForExistence(timeout: 5),
                      "with no stations the list must show its empty state")
        XCTAssertTrue(app.staticTexts["No stations yet"].exists)
    }

    /// RV.156: the Stations list carries its own add door, so a station can be
    /// named where stations are managed - not only mid-entry - and it appears
    /// in the list. The created name goes through the same deterministic rule
    /// the entry row uses (the two doors can never disagree).
    func testTheStationsListCanAddAStationByName() {
        let app = launch([])
        openGarage(app)
        openStations(app)

        // Even an empty list offers the door (the Garage's dashed-tile idiom);
        // the empty state's own copy points at it.
        XCTAssertTrue(app.staticTexts["stationsEmptyState"].waitForExistence(timeout: 5))
        let add = app.buttons["stationsAddStationButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "the Stations list must offer the add door")
        if !add.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(add.isHittable, "the add door must be reachable")
        add.tap()

        let alert = app.alerts["Add station"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the add door must present the naming dialog")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Shell")
        alert.buttons["Add"].tap()

        // The named station appears in the list and the empty state retires.
        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the named station must appear in the list")
        XCTAssertTrue(row.label.contains("Shell"),
                      "the list must show the station just named, got '\(row.label)'")
        XCTAssertFalse(app.staticTexts["stationsEmptyState"].exists,
                       "a non-empty list must not keep its empty state")
    }

    // MARK: - PJ.55 the favourite writer

    /// Walks the real user route - Garage tab -> Stations door -> the station's
    /// row -> per-station settings - with no `-presentScreen` teleport, so this
    /// also proves the screen (and therefore the toggle) is reachable without a
    /// debug flag. Language-independent identifiers only: the RU pass reuses it.
    private func openFirstStationSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))

        let link = app.buttons["garageStationsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "the Garage must always offer the Stations door")
        if !link.isHittable {
            app.swipeUp()
        }
        link.tap()

        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the seeded station must be listed")
        row.tap()
        XCTAssertTrue(app.switches["stationSettingsFavoriteToggle"].waitForExistence(timeout: 5),
                      "a station's settings must offer the favourite toggle (PJ.55)")
    }

    /// PJ.55: the toggle is reachable from the Garage and REVERSIBLE - on, then
    /// off, each flipping the persisted value. A one-way toggle, or one whose
    /// off state does not persist, is the same defect in a new costume.
    func testFavouriteToggleIsReachableFromTheGarageAndReversible() {
        let app = launch(["-seedStationSettings"])
        openFirstStationSettings(app)

        let toggle = app.switches["stationSettingsFavoriteToggle"]
        XCTAssertEqual(toggle.value as? String, "0",
                       "a freshly seeded station is not a favourite")
        toggle.tap()
        XCTAssertEqual(app.switches["stationSettingsFavoriteToggle"].value as? String, "1",
                       "turning the favourite on must persist")
        app.switches["stationSettingsFavoriteToggle"].tap()
        XCTAssertEqual(app.switches["stationSettingsFavoriteToggle"].value as? String, "0",
                       "turning the favourite off must persist")
    }

    /// PJ.55: both states survive a relaunch (the second and third launches keep
    /// the database, so a write that only touched view state would read back
    /// unchanged). This is the round trip hard rule 13 requires.
    func testFavouriteOnAndOffStatesSurviveRelaunch() {
        let app = launch(["-seedStationSettings"])
        openFirstStationSettings(app)
        app.switches["stationSettingsFavoriteToggle"].tap()
        XCTAssertEqual(app.switches["stationSettingsFavoriteToggle"].value as? String, "1")
        app.terminate()

        // Relaunch WITHOUT the database reset: the seed is idempotent, so the
        // stored favourite must read back ON.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-seedStationSettings"]
        relaunched.launch()
        openFirstStationSettings(relaunched)
        let on = relaunched.switches["stationSettingsFavoriteToggle"]
        XCTAssertEqual(on.value as? String, "1",
                       "the favourite must survive a relaunch")
        on.tap()
        XCTAssertEqual(relaunched.switches["stationSettingsFavoriteToggle"].value as? String, "0")
        relaunched.terminate()

        let third = XCUIApplication()
        third.launchArguments = ["-seedStationSettings"]
        third.launch()
        openFirstStationSettings(third)
        XCTAssertEqual(third.switches["stationSettingsFavoriteToggle"].value as? String, "0",
                       "the cleared state must survive a relaunch too")
    }

    /// PJ.55 RU: the control renders in Russian and still works. The identifier
    /// is language-independent, but the visible label must be the catalogue's
    /// Russian copy (hard rule 10) - the RU pass is where a missing translation
    /// shows.
    func testFavouriteToggleRendersInRussian() {
        let app = launch(["-seedStationSettings",
                          "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        openFirstStationSettings(app)

        let toggle = app.switches["stationSettingsFavoriteToggle"]
        XCTAssertTrue(toggle.label.contains("Избранная заправка"),
                      "the RU toggle label must be translated, got '\(toggle.label)'")
        toggle.tap()
        XCTAssertEqual(app.switches["stationSettingsFavoriteToggle"].value as? String, "1",
                       "the RU toggle must still write the favourite")
    }
}
