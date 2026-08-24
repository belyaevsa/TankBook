import XCTest

/// P1.9 Tank-level sheet tests. The two behaviours that carry the task:
/// the litres equivalence is shown when the car's tank capacity is known and
/// hidden behind the ERRORS.md hint when it is not, and the percentage the user
/// sets in the sheet is exactly what gets saved to the entry (a full round trip
/// through the edit form, reopen, and the row reflecting the stored value).
@MainActor
final class TankLevelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    /// Swipes the sheet's scroll view until the element's center clears the
    /// floating save bar (~660pt) - a row sitting under it would hand its tap
    /// to the save button. Targets the ScrollView element, never the app: a
    /// whole-app swipe can trigger the navigation stack's interactive pop.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0 ..< 6 where element.frame.midY > 660 {
            scrollView.swipeUp()
        }
    }

    // MARK: - The sheet: litres equivalence vs the no-capacity hint

    func testLitresEquivalenceShownWhenCapacityKnown() {
        let app = launch(args: ["-homeResetDatabase", "-seedTankLevel",
                                "-presentScreen", "tankLevel"])

        // ¾ is the suggested draft, so the equivalence reads 53 of 71 L.
        let litres = app.staticTexts["tankLevelLitresEquivalence"]
        XCTAssertTrue(litres.waitForExistence(timeout: 10))
        XCTAssertEqual(litres.label, "≈ 53 of 71 L")
        XCTAssertFalse(app.staticTexts["tankLevelNoCapacityHint"].exists)
        // The affordances are up, not just the text.
        XCTAssertTrue(app.buttons["tankLevelChip_75"].exists)
        XCTAssertTrue(app.buttons["tankLevelSetButton"].exists)
        XCTAssertTrue(app.buttons["tankLevelSkipButton"].exists)
    }

    func testNoCapacityShowsHintAndHidesLitres() {
        let app = launch(args: ["-homeResetDatabase", "-seedTankLevelNoCapacity",
                                "-presentScreen", "tankLevel"])

        let hint = app.staticTexts["tankLevelNoCapacityHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertEqual(hint.label, "Set tank size in Garage to see liters.")
        XCTAssertFalse(app.staticTexts["tankLevelLitresEquivalence"].exists)
        // Percentages still work - the sheet is not blocked without a capacity.
        XCTAssertTrue(app.buttons["tankLevelSetButton"].isEnabled)
    }

    // MARK: - The percentage set is what gets saved (ConfirmManual round trip)

    func testPercentageSetInSheetIsSavedAndSurvivesReopen() {
        // Reset first: the idempotent seed would otherwise accumulate identical
        // fills across test runs, and the S2 duplicate heuristic (30 min, 5%)
        // would merge this run's fill into a "Possible duplicate" card instead
        // of a normal log row.
        let app = launch(args: ["-homeResetDatabase", "-seedVehicleForUITests"])
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        // Set the level first (no keyboard up): toggle full off, open the
        // sheet, pick ¾, and the form row reflects it.
        let toggle = app.switches["manualFillUpIsFullToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let tankRow = app.buttons["tankLevelRow"]
        XCTAssertTrue(tankRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set level"].exists)

        scrollTo(tankRow, in: app)
        tankRow.tap()
        XCTAssertTrue(app.navigationBars["Tank level"].waitForExistence(timeout: 5),
                      "tapping the tank row must present the tank-level sheet")
        let chip = app.buttons["tankLevelChip_75"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.buttons["tankLevelSetButton"].waitForExistence(timeout: 5))
        app.buttons["tankLevelSetButton"].tap()
        XCTAssertTrue(rowShows("75%", in: app), "the form row must reflect the set level")
        XCTAssertFalse(app.buttons["tankLevelRow"].label.contains("Set level"))

        // Now the two typed values that enable save; the save bar rides above
        // the keyboard, so it stays tappable.
        let total = app.textFields["manualFillUpTotalField"]
        total.tap()
        total.typeText("71.02")
        let liters = app.textFields["manualFillUpLitersField"]
        liters.tap()
        liters.typeText("42.30")

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5))

        // Relaunch so the reopen is deterministic: Home's post-save refresh is
        // tied to the sheet-dismissal reappear, which iOS 26 does not always
        // fire - the log can otherwise still show only the seeded prior fill.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-seedVehicleForUITests"]
        relaunched.launch()

        // Reopen the saved entry in edit: the level is what was set, not a
        // default. The seed's prior fill is in the log too, and the newest is
        // first, so the first row is the saved (partial) fill.
        let logRows = relaunched.buttons.matching(identifier: "logEntryButton")
        XCTAssertTrue(logRows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(logRows.count, 2, "the saved fill must be in the log after relaunch")
        logRows.firstMatch.tap()
        XCTAssertTrue(relaunched.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        XCTAssertTrue(rowShows("75%", in: relaunched),
                      "the set level must survive a save and reload")
    }

    // MARK: - The sheet from Edit entry

    func testEditEntryTankRowOpensSheetAndReflectsLevel() {
        let app = launch(args: ["-homeResetDatabase", "-seedHomeEditHistory"])
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        let toggle = app.switches["manualFillUpIsFullToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let tankRow = app.buttons["tankLevelRow"]
        XCTAssertTrue(tankRow.waitForExistence(timeout: 5))
        scrollTo(tankRow, in: app)

        tankRow.tap()
        XCTAssertTrue(app.navigationBars["Tank level"].waitForExistence(timeout: 5),
                      "tapping the tank row in Edit entry must present the sheet")
        let chip = app.buttons["tankLevelChip_75"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        app.buttons["tankLevelSetButton"].tap()

        XCTAssertTrue(rowShows("75%", in: app),
                      "the Edit entry tank row must reflect the level the sheet set")
    }

    // MARK: - The sheet from ConfirmManual

    func testConfirmManualTankRowOpensSheetAndReflectsLevel() {
        let app = launch(args: ["-seedVehicleForUITests"])
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        // Turn the full-tank toggle off -> the tank row appears.
        let toggle = app.switches["manualFillUpIsFullToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let tankRow = app.buttons["tankLevelRow"]
        XCTAssertTrue(tankRow.waitForExistence(timeout: 5))

        // ½ from the chips, then Set.
        tankRow.tap()
        XCTAssertTrue(app.navigationBars["Tank level"].waitForExistence(timeout: 5),
                      "tapping the tank row must present the tank-level sheet")
        let chip = app.buttons["tankLevelChip_50"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        app.buttons["tankLevelSetButton"].tap()

        XCTAssertTrue(rowShows("50%", in: app),
                      "the ConfirmManual tank row must reflect the level the sheet set")
    }

    /// The tank row's value is combined into the button's accessibility label
    /// ("Tank after fill-up, 75%"), so assert on the label, not a standalone
    /// staticText - the same row renders in ConfirmManual and Edit entry.
    /// Polls up to `timeout` because a freshly-opened edit screen can take a
    /// beat to settle the row into the hierarchy.
    private func rowShows(_ value: String, in app: XCUIApplication,
                          timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let row = app.buttons["tankLevelRow"]
            if row.exists && row.label.contains(value) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let row = app.buttons["tankLevelRow"]
        return row.exists && row.label.contains(value)
    }
}
