import XCTest

// RV.264 - the review screen's intro carries two runtime counts, and the
// bottom-bar exit must name the preview it actually returns to. A String
// Catalog plural variation pluralises only one argument, so the composed
// sentence rendered "2 rows are ready. These 1 are missing something" and
// Russian mis-declined at every count. The fix is one full localised phrase per
// plural category, per count (two keys), and the exit label corrected to
// "Done · back to preview" (`reviewReturn()` goes to the preview).
//
// A separate file extending the same `ImportUITests` class keeps
// `ImportUITests.swift` under SwiftLint's 700-line file ceiling while
// `-only-testing:TankbookUITests/ImportUITests` still runs these.
@MainActor
extension ImportUITests {

    func testReviewIntroPluralisesTheMissingCountAndNamesThePreview() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportStationReview"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts[
            "1 row is ready. This 1 is missing something – fix one, or leave it out."
        ].exists, "the one-row review intro must use the singular for the missing count")

        let done = app.buttons["importReviewDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done · back to preview",
                       "the review exit must name the preview it returns to")
    }

    func testReviewIntroPluralisesTheMissingCountInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportStationReview"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts[
            "1 строка готова. Эта 1 строка неполная – исправьте или пропустите."
        ].exists, "the RU one-row review intro must decline the singular correctly")

        XCTAssertEqual(app.buttons["importReviewDoneButton"].label, "Готово · к просмотру",
                       "the RU review exit names the preview it returns to")
    }
}
