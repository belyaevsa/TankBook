import XCTest

// RV.116's L4 coverage, in its own file so ImportUITests.swift stays under
// SwiftLint's `file_length` error floor (the same split the date-format and
// read-failure extensions use). The suite name is unchanged - these still run
// under `-only-testing:TankbookUITests/ImportUITests`.
//
// The review gate must name the columns the format has no home for, with how
// many rows carried a value in each, and must never block Continue. The seed
// declares Driver (250 rows) and Payment method (12 rows) and the format
// declares them server-side. The assertion is the COUNT, not the presence of
// a sentence - a notice with no numbers is trivia.
@MainActor
extension ImportUITests {

    func testUnsupportedColumnsNoticeShowsCountsAndNeverBlocksContinue() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "unsupported",
                          "-importStubParse", "unsupported",
                          "-seedImportUnsupported"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10),
                      "the review gate must be on screen")

        XCTAssertTrue(app.otherElements["importUnsupportedNotice"].waitForExistence(timeout: 5),
                      "the gate must say what is not coming in")

        let driver = app.descendants(matching: .any)["importUnsupportedColumn-Driver"].firstMatch
        XCTAssertTrue(driver.waitForExistence(timeout: 5),
                      "the notice names the unsupported Driver column")
        XCTAssertTrue(driver.label.contains("250"),
                      "the notice must carry the row count; label was '\(driver.label)'")

        let payment = app.descendants(matching: .any)["importUnsupportedColumn-Payment method"].firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        XCTAssertTrue(payment.label.contains("12"),
                      "each column carries its own count; label was '\(payment.label)'")

        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "the notice is never a gate - Continue stays enabled")
    }

    func testUnsupportedColumnsNoticeShowsCountsInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "unsupported",
                          "-importStubParse", "unsupported",
                          "-seedImportUnsupported"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.otherElements["importUnsupportedNotice"].waitForExistence(timeout: 5),
                      "the RU gate must say what is not coming in")
        let driver = app.descendants(matching: .any)["importUnsupportedColumn-Driver"].firstMatch
        XCTAssertTrue(driver.waitForExistence(timeout: 5))
        XCTAssertTrue(driver.label.contains("250"),
                      "the RU count must render; label was '\(driver.label)'")
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "the RU notice never blocks Continue")
    }
}
