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
}
