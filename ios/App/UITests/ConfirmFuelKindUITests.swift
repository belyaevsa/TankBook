import XCTest

/// P2.3c (correcting P2.3b): the Confirm Fuel row offers a LIKELY set, never a
/// limit. `Vehicle.fuelKinds` is a suggestion, not a constraint (hard rule 13):
/// petrol grades share a tank, so a car configured for 95 is routinely filled
/// with 92 or 100. A car whose kinds include any petrol grade is offered ALL
/// petrol grades plus its other kinds; a diesel car is offered diesel (and its
/// other kinds), never the petrol grades. Nothing is ever blocked - every
/// `FuelKind` stays reachable through the correction affordance, on both the
/// multi-kind and the single-kind path. The dead end P2.3b shipped (a
/// `[95, LPG]` car that could not record anything else) is the defect these
/// tests exist to prove is gone.
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

    /// A petrol car is offered EVERY petrol grade as a chip, because grades
    /// share a tank (the owner's correction: a 95 car takes 92 and 100). The
    /// assertion is WHICH kinds, never how many: all four grades must be
    /// present, and diesel must not be a chip on a petrol car.
    func testPetrolCarOffersEveryPetrolGradeButNotDiesel() {
        let app = launchFuelRow()
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol92"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol95"].exists)
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol98"].exists,
                      "a 95 car is offered 98 - grades share a tank")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol100"].exists,
                      "a 95 car is offered 100 - grades share a tank")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_diesel"].exists,
                       "a petrol car must not be offered a diesel chip")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_lpg"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_e85"].exists)
    }

    /// The dead-end regression (the defect P2.3c exists to fix): a multi-kind
    /// car whose chips do not include a kind must still REACH that kind through
    /// the correction affordance, and the pick must land in the value. Asserting
    /// only that a menu exists would pass the bug; the select-and-lands
    /// assertion is the whole point.
    func testCorrectionMenuReachesAKindOutsideTheOfferSet() {
        let app = launchFuelRow("-seedVehiclePetrolLPG")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol95"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_diesel"].exists,
                       "diesel is not a chip on a petrol + LPG car")

        // The "+" correction menu is reachable and lists diesel.
        let more = app.buttons["manualFillUpFuelMoreMenu"]
        scrollClearOfSaveBar(app, more)
        XCTAssertTrue(more.isHittable, "the correction menu must be reachable")
        more.tap()
        let diesel = app.buttons["manualFillUpFuelCorrection_diesel"]
        XCTAssertTrue(diesel.waitForExistence(timeout: 5),
                      "the correction menu must list a kind outside the offer set")
        diesel.tap()

        // The pick lands in the value: diesel is now a selected chip.
        let dieselChip = app.buttons["manualFillUpFuelKind_diesel"]
        XCTAssertTrue(dieselChip.waitForExistence(timeout: 5),
                      "the selected kind must render as a chip")
        XCTAssertTrue(dieselChip.isSelected, "the corrected fuel must land in the value")
    }

    /// A diesel car is offered diesel and its other kinds, never a petrol chip.
    /// The car is a REAL multi-kind diesel (diesel + LPG - a conversion that
    /// exists), so the row renders its chooser and the assertion is exact.
    func testDieselCarIsOfferedDieselAndItsKindsNotPetrol() {
        let app = launchFuelRow("-seedVehicleDieselLPG")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_diesel"].waitForExistence(timeout: 5),
                      "a diesel car offers diesel")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_lpg"].exists,
                      "diesel + LPG is a real conversion, offered alongside diesel")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol95"].exists,
                       "a diesel car must not be offered a petrol chip")
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol92"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol98"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_petrol100"].exists)
    }

    /// Petrol + LPG is a real bi-fuel car: the row offers all four petrol
    /// grades PLUS LPG, and nothing else as a chip.
    func testPetrolAndLpgCarOffersAllPetrolGradesPlusLpg() {
        let app = launchFuelRow("-seedVehiclePetrolLPG")
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol95"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol92"].exists)
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol98"].exists)
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_petrol100"].exists)
        XCTAssertTrue(app.buttons["manualFillUpFuelKind_lpg"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_diesel"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_cng"].exists)
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_e85"].exists)
    }

    /// A single-kind car renders a STATIC value, not a chooser - the car burns
    /// one thing - and the value stays editable (hard rule 13): one tap opens
    /// the correction menu and the pick lands, including a kind the car was not
    /// configured for. Asserting only that the chooser is gone would ship the
    /// hard-rule-13 violation with a green test, so the editability is asserted
    /// right here.
    func testSingleKindDieselCarRendersStaticValueThatStaysEditable() {
        let app = launchFuelRow("-seedVehicleDieselOnly")
        // No chooser: there is no chip for the car's own kind.
        XCTAssertFalse(app.buttons["manualFillUpFuelKind_diesel"].waitForExistence(timeout: 2),
                       "a single-kind car must not render a chooser")
        // The static value is up and reads the car's kind.
        let value = app.buttons["manualFillUpFuelValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "Diesel")
        // Still correctable: tap it, pick a kind outside the car's set, the
        // row reflects it - the single-kind path is as permissive as the chips.
        scrollClearOfSaveBar(app, value)
        XCTAssertTrue(value.isHittable, "the fuel value must be reachable to be editable")
        value.tap()
        let petrol95 = app.buttons["manualFillUpFuelCorrection_petrol95"]
        XCTAssertTrue(petrol95.waitForExistence(timeout: 5),
                      "the correction menu must list the kinds")
        petrol95.tap()
        XCTAssertEqual(value.label, "95", "the corrected fuel must render")
    }

    /// Scroll an element clear of the pinned save bar (a `safeAreaInset` the
    /// accessibility tree does not model - `isHittable` turns true while the
    /// element sits under it, and a tap there lands on Save). Local copy of
    /// the ConfirmManualUITests helper, which is file-private.
    private func scrollClearOfSaveBar(_ app: XCUIApplication, _ element: XCUIElement) {
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
