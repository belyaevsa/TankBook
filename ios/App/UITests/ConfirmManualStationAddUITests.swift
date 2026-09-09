import XCTest

// MARK: - RV.156 the entry row can create a station

/// RV.156: the Station row is interactive in BOTH states. With no stations it
/// offers the add door (never the dead "Not set" label); with stations the menu
/// keeps working and gains the same door at its end, so a user with one station
/// can always add a second. The door names a station, the created station is
/// SELECTED on the entry (asserting selection, never merely `isHittable` - the
/// row's whole point is that naming produces a station, and the save reaches
/// the Garage list), and the row still fits at the largest text size in both
/// languages (frame geometry, the RV.84 anti-trap: `isHittable` reports true
/// for an element 86% clipped).
@MainActor
extension ConfirmManualUITests {

    /// Drives the naming dialog: type a name and confirm. The alert's field and
    /// actions are the system's own, so they are reached by title and label.
    private func rv156NameStation(_ name: String, in app: XCUIApplication) {
        let alert = app.alerts["Add station"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "tapping the add door must present the naming dialog")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        alert.buttons["Add"].tap()
    }

    /// The sheet's focus helper (its own copy - the main class's is private to
    /// its file). The stop condition is GEOMETRIC: `isHittable` is true under
    /// the pinned Save bar and a tap there would save the sheet.
    @discardableResult
    private func rv156FocusField(_ app: XCUIApplication,
                                 _ identifier: String) -> XCUIElement {
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

    private func rv156ScrollToReveal(_ app: XCUIApplication, _ element: XCUIElement) {
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 10 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if element.isHittable && element.frame.maxY < barTop - 8 { return }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { return }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
    }

    private func rv156WaitForLabel(_ element: XCUIElement, containing text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    /// The row's whole point (L4): on a car with NO stations the row is
    /// tappable, reaches a way to name one, and the named station is SELECTED
    /// on the entry - then the save at that station lands it in the Garage
    /// list, so a station was really produced, not merely a control tapped.
    func testEmptyStationRowNamesASelectedStationAndTheSaveReachesTheGarage() {
        let app = launch()
        openManualForm(app)

        // The dead "Not set" placeholder is gone: the row offers the add door.
        let addDoor = app.buttons["manualFillUpAddStationButton"]
        XCTAssertTrue(addDoor.waitForExistence(timeout: 10),
                      "with no stations the row must offer the add door")
        rv156ScrollToReveal(app, addDoor)
        XCTAssertFalse(app.buttons["manualFillUpStationButton"].exists,
                       "with no stations there is no menu yet")

        addDoor.tap()
        rv156NameStation("Prima Auto", in: app)

        // The created station is SELECTED on the entry - the row becomes the
        // pick menu whose label is the new station's name.
        let station = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(station.waitForExistence(timeout: 5),
                      "after naming, the row must become the menu with a selection")
        rv156WaitForLabel(station, containing: "Prima Auto")

        // Save at that station, then prove the station really exists where the
        // user manages it: the Garage Stations list.
        let total = rv156FocusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        let liters = rv156FocusField(app, "manualFillUpLitersField")
        liters.typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "the save must dismiss the sheet")

        let garageTab = app.buttons["tabbar.garage"]
        XCTAssertTrue(garageTab.waitForExistence(timeout: 5))
        garageTab.tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
        let stationsLink = app.buttons["garageStationsLink"]
        XCTAssertTrue(stationsLink.waitForExistence(timeout: 5))
        stationsLink.tap()
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 5))

        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the station named on the entry must appear in the Stations list")
        XCTAssertTrue(row.label.contains("Prima Auto"),
                      "the list must show the created station, got '\(row.label)'")
    }

    /// L4: on a car WITH stations the menu still works AND offers the add door
    /// - a user with one station must be able to add a second, never be locked
    /// into the single seeded row.
    func testStationMenuStillWorksAndOffersTheAddDoorWithStationsPresent() {
        let app = launch(args: ["-seedUnlocatedStation"])
        openManualForm(app)

        // One station on file: the row is the pick menu with no pre-selection
        // (the by-hand station cannot win a distance rung).
        let station = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(station.waitForExistence(timeout: 10))
        rv156ScrollToReveal(app, station)
        XCTAssertTrue(station.label.contains("Choose station"))

        // The menu still works: pick the existing station.
        station.tap()
        let prima = app.buttons["Prima Auto"]
        XCTAssertTrue(prima.waitForExistence(timeout: 5),
                      "the menu must still list the existing station")
        prima.tap()
        rv156WaitForLabel(station, containing: "Prima Auto")

        // And it offers the add door at its end: a second station is addable.
        station.tap()
        let addItem = app.buttons["manualFillUpAddStationMenuItem"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 5),
                      "the menu must offer the add door at its end")
        addItem.tap()
        rv156NameStation("Circle K Sadama", in: app)
        rv156WaitForLabel(station, containing: "Circle K Sadama")
    }

    // MARK: - Largest text size, EN and RU

    /// The add door must stay inside the window at the largest Dynamic Type
    /// size - English.
    func testStationAddRowFitsAtLargestTextSizeEnglish() {
        let app = launch(args: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"])
        openManualForm(app)
        let addDoor = app.buttons["manualFillUpAddStationButton"]
        XCTAssertTrue(addDoor.waitForExistence(timeout: 10))
        rv156ScrollToReveal(app, addDoor)
        rv156AssertInsideTheWindow(app, [addDoor])
    }

    /// The same at XXXL in Russian (RU copy runs longer - «Добавить заправку»
    /// beside a large "Station" label must never clip or run off-screen).
    func testStationAddRowFitsAtLargestTextSizeRussian() {
        let app = launch(args: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"])
        openManualForm(app)
        let addDoor = app.buttons["manualFillUpAddStationButton"]
        XCTAssertTrue(addDoor.waitForExistence(timeout: 10))
        rv156ScrollToReveal(app, addDoor)
        rv156AssertInsideTheWindow(app, [addDoor])
        // Restore the app's persisted language for suites running after this one.
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    /// Frame geometry, never `isHittable`: an element 86% clipped still reports
    /// hittable (RV.84), so the check is that every element's frame lies inside
    /// the window.
    private func rv156AssertInsideTheWindow(_ app: XCUIApplication,
                                            _ elements: [XCUIElement]) {
        let window = app.windows.firstMatch.frame
        for element in elements {
            XCTAssertGreaterThanOrEqual(element.frame.maxX, 0)
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX,
                                     "\(element.identifier) runs off-screen at XXXL")
            XCTAssertGreaterThanOrEqual(element.frame.maxY, window.minY,
                                        "\(element.identifier) sits above the window")
            XCTAssertLessThanOrEqual(element.frame.maxY, window.maxY,
                                     "\(element.identifier) sits below the window")
        }
    }
}
