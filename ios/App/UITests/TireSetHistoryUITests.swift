import XCTest

/// The tire set's life (L4, docs/JOURNEYS.md J7b). A reading typed at the swap
/// reaches the set's history, and a stint's reading stays editable from that
/// history afterwards (hard rule 13). The assertions read what the history
/// SHOWS after each write, not that the fields exist.
@MainActor
final class TireSetHistoryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-homeResetDatabase"] : [])
            + arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    func testTheSwapReadingReachesTheSetsHistory() {
        let app = launch(["-seedTireSetsNoOdometer", "-presentScreen", "serviceEntry"])
        let tiresMode = app.buttons["serviceEntryModeTires"]
        XCTAssertTrue(tiresMode.waitForExistence(timeout: 10))
        tiresMode.tap()
        let picker = app.buttons["serviceEntryTireSetPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let winter = app.buttons["Winter Nokian"]
        XCTAssertTrue(winter.waitForExistence(timeout: 5))
        winter.tap()

        // The reading is offered once a set is mounted; a depth that is not one
        // refuses to save and names the fix.
        let depth = app.textFields["tireReadingDepthField"]
        XCTAssertTrue(depth.waitForExistence(timeout: 5), "the reading appears with a mounted set")
        let odometer = app.textFields["serviceEntryOdometerField"]
        odometer.tap()
        odometer.typeText("120000")
        depth.tap()
        depth.typeText("..")
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertFalse(save.isEnabled, "a depth that is not a number must not be dropped silently")
        XCTAssertTrue(app.staticTexts["serviceEntrySaveHint"].exists)
        depth.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "6.4")
        let note = app.textFields["tireReadingNoteField"]
        note.tap()
        note.typeText("Even wear")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(tiresMode.waitForNonExistence(timeout: 10))

        // The set's own screen now shows the stint that swap started, on the car,
        // with the reading taken at it.
        let history = launch(["-presentScreen", "tireSets"], reset: false)
        let row = history.staticTexts["Winter Nokian"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(history.staticTexts["tireStintOnCar"].waitForExistence(timeout: 5))
        XCTAssertTrue(history.buttons["tireStintReading"].label.contains("6.4 mm · Even wear"),
                      "the history shows \(history.buttons["tireStintReading"].label)")
    }

    func testAStintsReadingIsEditableFromTheHistory() {
        let app = launch(["-seedTireSetHistory", "-presentScreen", "tireSetHistory"])
        let rows = app.otherElements.matching(identifier: "tireStintRow")
        XCTAssertTrue(app.buttons["tireStintReading"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "tireStintReading").count, 2,
                       "two stints of the winter set, rows seen: \(rows.count)")

        // The newest stint is first; change its reading.
        let current = app.buttons.matching(identifier: "tireStintReading").element(boundBy: 0)
        XCTAssertTrue(current.label.contains("7.2 mm"), "seeded reading was \(current.label)")
        current.tap()
        let depth = app.textFields["tireReadingDepthField"]
        XCTAssertTrue(depth.waitForExistence(timeout: 5))
        depth.tap()
        depth.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        depth.typeText("5.9")
        app.buttons["tireReadingSaveButton"].tap()
        XCTAssertTrue(depth.waitForNonExistence(timeout: 5))

        let edited = app.buttons.matching(identifier: "tireStintReading").element(boundBy: 0)
        XCTAssertTrue(edited.label.contains("5.9 mm · Even wear"), "after the edit: \(edited.label)")
        // The older stint is untouched.
        XCTAssertTrue(app.buttons.matching(identifier: "tireStintReading").element(boundBy: 1)
            .label.contains("9.5 mm"))
    }
}
