import XCTest

// MARK: - RV.161 the scanned station as an editable pre-fill

/// The scan resolved the receipt's station line; the Confirm sheet must show it
/// as a default input the user can change (hard rule 13), never as a hidden
/// write and never as a locked fact. The seed (`-seedConfirmPrefillStation`)
/// carries the extraction the app's own parser produces for a Gazpromneft /
/// Circle K slip; the test asserts WHICH brand is on the row, not that a row
/// exists.
@MainActor
extension ConfirmManualUITests {

    func testScannedStationShowsAsTheSelectedEditablePrefill() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-seedConfirmPrefillStation"]
        app.launch()
        openManualForm(app)

        // The station row is a menu whose label is the scanned brand - the value
        // the receipt named, shown as the selection the user can change.
        let stationButton = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(stationButton.waitForExistence(timeout: 10),
                      "a scanned station must make the row a menu")
        XCTAssertTrue(stationButton.label.contains("Circle K Sikupilli"),
                      "the scanned brand must be the selected pre-fill, got '\(stationButton.label)'")

        // Changeable: the menu opens and offers the add door, so the scanned
        // name is a default input, never a fact.
        stationButton.tap()
        XCTAssertTrue(app.buttons["manualFillUpAddStationMenuItem"].waitForExistence(timeout: 5),
                      "the scanned station must stay changeable")
    }
}
