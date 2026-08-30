import XCTest

/// P2.3b: the Confirm Fuel row offers exactly `vehicle.fuelKinds` - never a
/// kind the car cannot burn - and a single-kind car renders a static value
/// instead of a chooser, while staying correctable (hard rule 13). The seeds
/// used to configure the test car as `[.petrol95, .diesel]`, a car that burns
/// both, which does not exist, so the row honestly offered a Diesel chip on a
/// petrol car.
///
/// Each test launches with a clean database (`-homeResetDatabase`) and its own
/// fuel-kind seed, so the offer set asserted is the seed's, never a leftover
/// launch's. `ManualFillUpTestSeed.fuelKindsFromArguments` maps the
/// `-seedVehicle*` variants to the seeded car's kinds.
@MainActor
final class ConfirmFuelKindUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchFuelRow(_ seed: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase"]
            + (seed.map { [$0] } ?? [])
        app.launch()
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        return app
    }

    /// A diesel car is never offered a petrol grade. The car is a REAL
    /// multi-kind diesel (diesel + LPG - a conversion that exists), so the row
    /// renders its chooser and the assertion is exact: Diesel and LPG chips
    /// are offered, no petrol grade is. A single-kind diesel car would render
    /// a static value, not a chooser, so it cannot carry the "not offered
    /// petrol" assertion - that is what the static-value test covers.
    func testDieselCarIsNeverOfferedPetrol() {
        let app = launchFuelRow("-seedVehicleDieselLPG")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_diesel"].waitForExistence(timeout: 5),
                      "a diesel car offers diesel")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_lpg"].exists,
                      "diesel + LPG is a real conversion, offered alongside diesel")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol95"].exists,
                       "a diesel car must not be offered petrol")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol92"].exists,
                       "a diesel car must not be offered any petrol grade")
    }

    /// The converse, so a filter inverted the wrong way cannot pass: a petrol
    /// car is never offered diesel, and a 92+95 car is offered exactly those
    /// two grades - the assertion is WHICH kinds, never how many.
    func testPetrolCarWith92And95IsOfferedExactlyThoseGrades() {
        let app = launchFuelRow("-seedVehiclePetrolMulti")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol92"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol95"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_diesel"].exists,
                       "a petrol car must not be offered diesel")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol98"].exists,
                       "a 92+95 car is offered exactly 92 and 95")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_lpg"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_e85"].exists)
    }

    /// Petrol + LPG is a real bi-fuel car: the row offers exactly that pair.
    func testPetrolAndLpgCarIsOfferedExactlyThoseTwo() {
        let app = launchFuelRow("-seedVehiclePetrolLPG")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol95"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_lpg"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_diesel"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol92"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_cng"].exists)
    }

    /// A single-kind car renders a STATIC value, not a chooser - the car burns
    /// one thing - and the value stays editable (hard rule 13): one tap opens
    /// the correction menu and the pick lands. Asserting only that the chooser
    /// is gone would ship the hard-rule-13 violation with a green test, so the
    /// editability is asserted right here.
    func testSingleKindCarRendersStaticValueThatStaysEditable() {
        let app = launchFuelRow()
        // No chooser: there is no chip for the car's own kind.
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol95"].waitForExistence(timeout: 2),
                       "a single-kind car must not render a chooser")
        // The static value is up and reads the car's kind.
        let value = app.buttons["manualFillUpFuelValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "95")
        // Still correctable: tap it, pick a different kind, the row reflects it.
        scrollFuelValueClearOfSaveBar(app, value)
        XCTAssertTrue(value.isHittable, "the fuel value must be reachable to be editable")
        value.tap()
        let diesel = app.buttons["manualFillUpFuelCorrection_diesel"]
        XCTAssertTrue(diesel.waitForExistence(timeout: 5),
                      "the correction menu must list the kinds")
        diesel.tap()
        XCTAssertEqual(value.label, "Diesel", "the corrected fuel must render")
    }

    /// Scroll an element clear of the pinned save bar (a `safeAreaInset` the
    /// accessibility tree does not model - `isHittable` turns true while the
    /// element sits under it, and a tap there lands on Save). Local copy of
    /// the ConfirmManualUITests helper, which is file-private.
    private func scrollFuelValueClearOfSaveBar(_ app: XCUIApplication, _ element: XCUIElement) {
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
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
}
