import XCTest

// MARK: - RV.150 the fill-up save stamps the station end to end

/// RV.150: saving a fill-up at a station writes the Station fields the
/// suggestion ranks by - lastUsedAt, the bought defaults, and a missing
/// location adopted from the fix the Confirm sheet already read. This drives
/// the whole path through the real UI: the by-hand fixture is a station with
/// NO location and NO lastUsedAt (the exact state that hid the defect), the
/// save happens in the Confirm sheet, and the stamp is then PROVEN where the
/// product decision says it must be visible - the Garage's per-station
/// settings - not merely by a field nobody can see.
@MainActor
extension ConfirmManualUITests {

    /// This file's own copy of the sheet's focus helper: `focusField` in
    /// ConfirmManualUITests.swift is `private`, so a cross-file extension needs
    /// its own (the same pattern NumericInputUITests uses). The stop condition
    /// is GEOMETRIC - `isHittable` is true under the pinned Save bar and a tap
    /// there would save the sheet.
    @discardableResult
    private func focusField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if field.isHittable && field.frame.maxY < barTop - 8 { break }
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
        return field
    }

    func testSavingAtAStationStampsItAndTheLocationShowsInTheGarage() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedUnlocatedStation",
                               "-seedStationLocation", "59.4378,24.7536"]
        app.launch()
        openManualForm(app)

        // The by-hand fixture's station cannot win a distance rung (no
        // location, no lastUsedAt), so the row offers the menu, not a
        // pre-selection; the user picks it.
        let stationButton = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(stationButton.waitForExistence(timeout: 10))
        XCTAssertTrue(stationButton.label.contains("Choose station"),
                      "an unlocated, never-used station must not be pre-selected, got '\(stationButton.label)'")
        stationButton.tap()
        let prima = app.buttons["Prima Auto"]
        XCTAssertTrue(prima.waitForExistence(timeout: 5))
        prima.tap()

        // Type two of three so Save unlocks, then save.
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        let liters = focusField(app, "manualFillUpLitersField")
        liters.typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // The save returns to Home; the stamp must now be visible where the
        // decision says it lives - the station's settings in the Garage.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "the save must dismiss the sheet")

        let garageTab = app.buttons["tabbar.garage"]
        XCTAssertTrue(garageTab.waitForExistence(timeout: 5))
        garageTab.tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))

        let stationsLink = app.buttons["garageStationsLink"]
        XCTAssertTrue(stationsLink.waitForExistence(timeout: 5),
                      "the Garage must offer the Stations door")
        stationsLink.tap()
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 5))

        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the stamped station must be listed")
        XCTAssertTrue(row.label.contains("Prima Auto"),
                      "the station just saved at must be on the list, got '\(row.label)'")
        row.tap()

        // The captured coordinate - the by-hand station had none before the
        // save - is now visible, and the control that clears it is present.
        XCTAssertTrue(app.navigationBars["Station"].waitForExistence(timeout: 5))
        let value = app.staticTexts["stationSettingsLocationValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "59.4378, 24.7536",
                       "the save must have adopted the fix the Confirm sheet read, got '\(value.label)'")

        // Property 1: the captured location is clearable in the Garage.
        let remove = app.buttons["stationSettingsRemoveLocation"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5),
                      "a station with a captured location must offer the removal control")
        remove.tap()
        XCTAssertTrue(app.staticTexts["Not set"].waitForExistence(timeout: 5),
                      "removing the location must return the row to its honest Not set state")
        XCTAssertFalse(app.buttons["stationSettingsRemoveLocation"].exists,
                       "with no location there is nothing left to remove")
    }
}
