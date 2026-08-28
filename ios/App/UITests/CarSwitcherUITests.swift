import XCTest

/// P1.11 Car switcher UI tests (design/screens/CarSwitcher.dc.html). The sheet
/// is the app's multi-vehicle heart: every car with its OWN vitals (per-vehicle
/// units - L/100 for petrol, kWh/100 for EV), archived cars dimmed and out of
/// active stats, and switching feeds Home and the log stream the SAME car the
/// switcher just picked (the selected-car invariant). The free-tier limit sheet
/// is the ONE monetization surface (docs/ERRORS.md -> Car switcher / Garage).
@MainActor
final class CarSwitcherUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + args
        app.launch()
        return app
    }

    private func rows(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(identifier: "carSwitcherRow").allElementsBoundByIndex
    }

    private func openSwitcher(_ app: XCUIApplication) {
        let button = app.buttons["carSwitcherButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))
    }

    // MARK: - The garage list

    /// The switcher lists every car with its own vitals - per-vehicle units on
    /// one screen (the artboard's whole point) - and the archived row renders
    /// distinctly, dimmed and not a selectable live car.
    func testSwitcherListsCarsWithOwnVitalsAndDistinctArchivedRow() {
        let app = launch(args: ["-seedHomeCarSwitcher"])
        openSwitcher(app)

        // Two live cars (Volvo petrol, ID.4 EV) plus one archived (BMW).
        let live = rows(app)
        XCTAssertEqual(live.count, 2, "exactly the two live cars are selectable rows")
        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherArchivedRow").count, 1)

        // Each row carries its OWN vitals, in ITS OWN unit: the petrol car
        // reports L/100, the EV kWh/100 - never a global unit.
        let volvo = live[0].label
        XCTAssertTrue(volvo.contains("Volvo V60"), "first row is the petrol car, got \(volvo)")
        XCTAssertTrue(volvo.contains("L/100"), "petrol car must report L/100, got \(volvo)")
        XCTAssertTrue(volvo.contains("119"), "petrol odometer present, got \(volvo)")

        let id4 = live[1].label
        XCTAssertTrue(id4.contains("ID.4"), "second row is the EV, got \(id4)")
        XCTAssertTrue(id4.contains("kWh/100"), "EV must report kWh/100, got \(id4)")
        XCTAssertTrue(id4.contains("31"), "EV odometer present, got \(id4)")

        // The archived row is its own affordance, honestly labelled (J13).
        let archived = app.buttons["carSwitcherArchivedRow"]
        XCTAssertTrue(archived.label.contains("BMW 320d"))
        XCTAssertTrue(archived.label.contains("Archived"))

        // The footer states the invariant in the user's words.
        XCTAssertTrue(app.staticTexts["carSwitcherFooter"].exists)
        XCTAssertTrue(app.buttons["carSwitcherAddCar"].exists)
    }

    /// Selecting a car persists it and switches Home AND the log stream to that
    /// car's data - the capture-logs-to-the-selected-car invariant, end to end.
    func testSwitchingChangesHomeGarageCardAndLogStream() {
        let app = launch(args: ["-seedHomeCarSwitcher"])

        // Home starts on the first live car (Volvo): its name on the garage
        // card, its fuel-kind "95" rows in the log stream.
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["95"].firstMatch.waitForExistence(timeout: 5),
                      "the petrol car's log rows must be on screen")

        openSwitcher(app)
        // Scoped to the sheet's own rows: the Garage tab root renders the same
        // cars, and an inactive tab's content is visible to XCUITest (opacity +
        // accessibilityHidden do not remove it from element queries), so an
        // unscoped label query would match the hidden Garage row first and tap
        // the wrong element.
        let id4 = app.buttons.matching(identifier: "carSwitcherRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "ID.4")).firstMatch
        XCTAssertTrue(id4.waitForExistence(timeout: 5))
        id4.tap()

        // The sheet dismisses and Home now shows the SAME car the switcher
        // picked: the ID.4's garage card and its Ionity charge rows, with the
        // petrol car's rows gone.
        XCTAssertTrue(app.staticTexts["ID.4"].waitForExistence(timeout: 10),
                      "Home must switch to the selected car")
        XCTAssertTrue(app.staticTexts["Ionity"].firstMatch.waitForExistence(timeout: 5),
                      "the EV's log stream must render after the switch")
        XCTAssertFalse(app.staticTexts["95"].firstMatch.exists,
                       "the previous car's log rows must be gone")
        XCTAssertFalse(app.navigationBars["My garage"].exists,
                       "selecting must dismiss the sheet")
    }

    // MARK: - The free-tier limit sheet (the ONE monetization surface)

    /// At the cap, "Add car" shows the limit sheet with all three next steps
    /// (Archive a car · Pro · cancel) - and cancelling leaves every car intact
    /// (existing cars are never locked, the anti-CarScope rule).
    func testLimitSheetShowsAllThreeNextStepsAndCancelLeavesEverythingIntact() {
        let app = launch(args: ["-seedHomeCarSwitcherLimit"])
        openSwitcher(app)

        XCTAssertEqual(rows(app).count, 3, "three live cars sit at the cap")

        app.buttons["carSwitcherAddCar"].tap()

        // The cap explanation, verbatim from docs/ERRORS.md.
        XCTAssertTrue(app.staticTexts["Free keeps up to 3 cars. Archive one, or go Pro."]
            .waitForExistence(timeout: 5))

        // All three next steps are present and reachable.
        let archive = app.buttons["carLimitArchiveButton"]
        let pro = app.buttons["carLimitProButton"]
        let cancel = app.buttons["carLimitCancelButton"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5) && archive.isHittable)
        XCTAssertTrue(pro.exists && pro.isHittable)
        XCTAssertTrue(cancel.exists && cancel.isHittable)

        // Cancel: the limit sheet goes away, nothing was removed or changed.
        cancel.tap()
        let dismissed = NSPredicate(format: "NOT (exists == 1)")
        expectation(for: dismissed, evaluatedWith: app.staticTexts[
            "Free keeps up to 3 cars. Archive one, or go Pro."])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(rows(app).count, 3, "cancelling must leave all cars intact")
        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherArchivedRow").count, 1,
                       "cancelling must not touch the archived car either")
        XCTAssertTrue(app.navigationBars["My garage"].exists,
                      "cancel leaves the switcher open for a different choice")
    }
}
