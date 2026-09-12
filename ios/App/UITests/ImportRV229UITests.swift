import XCTest

// RV.229 - the import review must not label a CHECK 5 consumption outlier
// "Breaks the timeline". The odometer and date are internally consistent, so
// the fields to question are the litres and the odometer: a different label
// and next step (hard rule 7). The seed's second fill implies 1.6 L/100km
// (8 L over 500 km), below the ICE band, while the order and pace are clean -
// so the ONLY flag is the outlier.
//
// A separate file extending the same `ImportUITests` class keeps
// `ImportUITests.swift` under SwiftLint's 700-line file ceiling while
// `-only-testing:TankbookUITests/ImportUITests` still runs these.
@MainActor
extension ImportUITests {

    func testConsumptionOutlierRowShowsItsOwnLabelAndChecks() {
        let app = launch(["-presentScreen", "importWizard", "-seedImportConsumption"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        let row = app.otherElements["importReviewRow-2"]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the outlier row is in the review list")
        XCTAssertTrue(app.staticTexts["Unusual consumption"].exists,
                      "the consumption outlier wears its own label, never the timeline's")
        XCTAssertFalse(app.staticTexts["Breaks the timeline"].exists,
                       "a consumption-only row must not be labelled a timeline break")
        let detail = app.descendants(matching: .any)["importReviewConsumptionDetail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "the amber consumption detail renders under the badge")
        XCTAssertTrue(app.buttons["Check litres"].exists,
                      "the litres check is the first next step (hard rule 7)")
        XCTAssertTrue(app.buttons["Check odometer"].exists,
                      "the odometer check is the second next step")
    }

    func testConsumptionOutlierRowShowsItsOwnLabelAndChecksInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard", "-seedImportConsumption"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["Необычный расход"].waitForExistence(timeout: 5),
                      "the RU consumption label is localised, not the English key")
        let detail = app.descendants(matching: .any)["importReviewConsumptionDetail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "the RU amber consumption detail renders under the badge")
        XCTAssertTrue(app.buttons["Проверить литры"].exists,
                      "the RU litres check is the first next step")
        XCTAssertTrue(app.buttons["Проверить пробег"].exists,
                      "the RU odometer check is the second next step")
    }
}
