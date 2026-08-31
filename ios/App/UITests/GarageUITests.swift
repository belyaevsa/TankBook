import XCTest

/// P6.4 Garage tab root UI tests. The tab is the real screen behind the third
/// tab (docs/SCREENMAP.md): the vehicle grid, where each car leads to its
/// detail (per-car settings - hard rule 13), the selected car is marked, and
/// "Add car" shows the free-tier limit sheet at the cap - the ONE monetization
/// surface, never an error, never mid-capture (docs/ERRORS.md).
@MainActor
final class GarageUITests: XCTestCase {

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
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    /// The live car rows (the archived one is a separate identifier).
    private func liveRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "garageCarRow")
    }

    // MARK: - The vehicle grid renders every car

    /// The artboard garage (the Car switcher seed's state, shared): two live
    /// cars (Volvo V60 petrol, ID.4 EV) and one archived (BMW 320d), each with
    /// its own vitals in its own units.
    func testGarageShowsEveryCarWithVitals() {
        let app = launch(["-seedHomeCarSwitcher"])
        openGarage(app)

        XCTAssertEqual(liveRows(app).count, 2, "both live cars render as rows")
        XCTAssertEqual(app.buttons.matching(identifier: "garageArchivedRow").count, 1,
                       "the archived car stays visible, dimmed and honest")

        // The selected car's row (Home's default) carries the selected marker in
        // its accessibility label - asserted through the label so the marker is
        // not just a dot nobody can read.
        let selectedRows = liveRows(app).matching(NSPredicate(format: "label CONTAINS %@", "Selected"))
        XCTAssertEqual(selectedRows.count, 1, "exactly one car is marked selected")
        XCTAssertTrue(selectedRows.firstMatch.label.contains("Volvo V60"),
                      "the selected marker is on the default car")
    }

    /// The vitals line is real data, not a placeholder: the Volvo reports its
    /// odometer and L/100 in the row's label, so a grid of empty cards could
    /// never pass.
    func testGarageVitalsAreDerivedNotStubbed() {
        let app = launch(["-seedHomeCarSwitcher"])
        openGarage(app)

        let volvo = liveRows(app).matching(NSPredicate(format: "label CONTAINS %@", "Volvo"))
        XCTAssertEqual(volvo.count, 1)
        // The odometer group separator is a no-break space (U+00A0,
        // OdometerFormat), so assert on the trailing group + unit, not the
        // full figure.
        XCTAssertTrue(volvo.firstMatch.label.contains("486 km"),
                      "the vitals carry the derived odometer")
        XCTAssertTrue(volvo.firstMatch.label.contains("L/100"),
                      "a fuel car reports its own consumption unit")
    }

    /// Every car card leads to its detail - the screen that makes per-car
    /// settings editable (hard rule 13). Tapping must land on the detail for
    /// THAT car, not just any screen.
    func testGarageRowNavigatesToVehicleDetail() {
        let app = launch(["-seedHomeCarSwitcher"])
        openGarage(app)

        let firstRow = liveRows(app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "garageCarRow never appeared")
        firstRow.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5),
                      "a live car card pushes the vehicle detail")
        let name = app.textFields["vehicleDetailNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the detail screen loaded with its form")
        XCTAssertEqual(name.value as? String, "Volvo V60",
                       "the tapped car's detail, not another car's")
    }

    // MARK: - Empty and limit states

    /// A garage with no cars is an honest empty state, not a wall - Add car is
    /// still reachable.
    func testGarageShowsEmptyStateWithoutCars() {
        let app = launch([])
        openGarage(app)

        XCTAssertTrue(app.staticTexts["No cars yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["garageAddCar"].exists, "Add car is reachable from the empty state")
    }

    /// At the free-tier cap, "Add car" shows the limit sheet - the ONE
    /// monetization surface - and cancelling leaves every car intact.
    func testGarageAddCarAtCapShowsLimitSheet() {
        let app = launch(["-seedHomeCarSwitcherLimit"])
        openGarage(app)

        XCTAssertEqual(liveRows(app).count, 3, "three live cars sit at the cap")

        let addCar = app.buttons["garageAddCar"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 5), "garageAddCar never appeared")
        addCar.tap()

        XCTAssertTrue(app.staticTexts["Free keeps up to 3 cars. Archive one, or go Pro."]
            .waitForExistence(timeout: 5), "the cap explanation is the sheet, not an error")
        XCTAssertTrue(app.buttons["carLimitArchiveButton"].exists)
        XCTAssertTrue(app.buttons["carLimitProButton"].exists)
        XCTAssertTrue(app.buttons["carLimitCancelButton"].exists)

        app.buttons["carLimitCancelButton"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5),
                      "cancel leaves the garage intact and on the tab")
        XCTAssertEqual(liveRows(app).count, 3, "cancelling must not remove a car")
    }

    /// Below the cap, Add car navigates straight to the form - the cap check is
    /// a gate, never an obstacle for the free tier.
    func testGarageAddCarBelowCapNavigatesToForm() {
        let app = launch(["-seedHomeCarSwitcher"])
        openGarage(app)

        let addCar = app.buttons["garageAddCar"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 5), "garageAddCar never appeared")
        addCar.tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5),
                      "with a free slot, Add car opens the form")
    }
}
