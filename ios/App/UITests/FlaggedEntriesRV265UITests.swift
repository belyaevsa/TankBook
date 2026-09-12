import XCTest

// RV.265 - the account-wide "Needs a look" list rendered a CHECK 5 consumption
// flag as the generic triangle + "car · date", indistinguishable from a
// timeline break until the row was opened. The excluded list and the import
// review already caption the flag "Unusual consumption – check the litres or
// odometer"; this list now gives the same reason through the same label table,
// and a timeline row keeps its own caption, so the two differ by words AND by
// identifier.
//
// A separate file extending the same `FlaggedEntriesUITests` class keeps
// `FlaggedEntriesUITests.swift` under SwiftLint's body-length floor while
// `-only-testing:TankbookUITests/FlaggedEntriesUITests` still runs these.
@MainActor
extension FlaggedEntriesUITests {

    private func openConsumptionFlaggedList(_ arguments: [String],
                                            title: String = "Needs a look") -> XCUIApplication {
        let app = launch(["-presentScreen", "settings",
                          "-seedSettingsFlaggedConsumption"] + arguments)
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the seeded conflict must show the Settings flagged row")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10),
                      "the flagged row must open the filtered list")
        waitForFlaggedRowCount(2, in: app)
        return app
    }

    func testConsumptionFlaggedRowNamesItsReasonDistinctFromTheTimelineRow() {
        let app = openConsumptionFlaggedList([])

        let consumption = app.staticTexts["flaggedEntryConsumptionReason"]
        XCTAssertTrue(consumption.waitForExistence(timeout: 5),
                      "the consumption-flagged row must name its own reason")
        XCTAssertEqual(consumption.label,
                       "Unusual consumption – check the litres or odometer",
                       "the consumption caption is the excluded list's own words")

        let timeline = app.staticTexts["flaggedEntryTimelineReason"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5),
                      "the timeline-flagged row keeps its own reason caption")
        XCTAssertEqual(timeline.label, "Timeline conflict – check the odometer or date")
        XCTAssertNotEqual(consumption.identifier, timeline.identifier,
                          "the two reasons must be distinguishable by identifier")
    }

    func testConsumptionFlaggedRowNamesItsReasonInRussian() {
        let app = openConsumptionFlaggedList(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"],
                                             title: "Требуют внимания")

        let consumption = app.staticTexts["flaggedEntryConsumptionReason"]
        XCTAssertTrue(consumption.waitForExistence(timeout: 5),
                      "the RU consumption-flagged row must name its own reason")
        XCTAssertEqual(consumption.label, "Необычный расход – проверьте литры или пробег",
                       "the RU consumption caption is localised, not the English key")

        let timeline = app.staticTexts["flaggedEntryTimelineReason"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertEqual(timeline.label, "Конфликт в хронологии – проверьте пробег или дату")
    }
}
