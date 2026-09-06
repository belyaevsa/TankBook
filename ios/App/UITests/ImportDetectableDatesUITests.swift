import XCTest

// RV.85 - a file that answers its own date format is not asked (L4). The
// owner's defect: the parser counted rows that were INDIVIDUALLY ambiguous and
// asked the user, never noticing another row in the same file settled the
// order. One export has one format, so a file any row proves M/D or D/M is
// resolved server-side and returns no `dateFormat` ambiguity - the question
// must not appear, and the dates shown must be the RESOLVED ones.
//
// The parse itself runs server-side (hard rule 9's named exception), so L4
// drives a stub of what the post-RV.85 server returns for a D/M-proven file
// (12/01 and 13/05 only read day-first): resolved candidate dates, NO
// `dateFormat` ambiguity. The vacuous trap this suite exists to avoid is
// asserting the question is absent without asserting the dates came out right -
// a parser that dropped the question and guessed would pass the first half
// alone. The date-range assertion IS the second half: the resolved readings are
// January and May 2026, where an M/D guess would read 12/01 as December and
// could not read 13/05 at all.
//
// The suite lives in its own file so `ImportUITests.swift` stays under the
// SwiftLint file-length ceiling.

@MainActor
final class ImportDetectableDatesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    func testDetectableFileAsksNoDateFormatQuestionAndShowsResolvedDates() {
        let app = launch(["-AppleLocale", "en_US",
                          "-presentScreen", "importWizard", "-seedImportResolvedDates"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        // The question must not appear: the file's rows proved D/M, so the
        // server resolved every date and returned no ambiguity (asking when the
        // answer is on disk is the RV.85 defect).
        XCTAssertEqual(app.otherElements.matching(identifier: "importDateFormatQuestion").count, 0,
                       "a file that proves its own date order must not be asked the date-format question")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "read either way")).firstMatch.exists,
            "the date-format question's copy must not render either")

        // And because no question is asked, nothing gates the confirm.
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "no dateFormat question means confirm needs no answer first")

        // The dates half - the half that matters. The resolved day-first
        // readings are January and May 2026; the assertion is the rendered
        // range, never merely the absence of the question.
        let dateRange = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Jan 2026 – May 2026")).firstMatch
        XCTAssertTrue(dateRange.waitForExistence(timeout: 5),
                      "the preview's date range must be the resolved Jan 2026 – May 2026")
    }

    func testDetectableFileAsksNoDateFormatQuestionInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard", "-seedImportResolvedDates"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        XCTAssertEqual(app.otherElements.matching(identifier: "importDateFormatQuestion").count, 0,
                       "RU: a file that proves its own date order must not be asked")
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "RU: no dateFormat question means confirm needs no answer first")

        // The resolved range in the app's own locale, computed with the same
        // month-year template the preview uses so the assertion names the
        // resolved months rather than assuming the exact abbreviation.
        let from = Self.monthYear(Date(timeIntervalSince1970: 1_768_176_000), locale: "ru_RU")
        let to = Self.monthYear(Date(timeIntervalSince1970: 1_778_630_400), locale: "ru_RU")
        let dateRange = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "\(from) – \(to)")).firstMatch
        XCTAssertTrue(dateRange.waitForExistence(timeout: 5),
                      "RU: the preview's date range must be the resolved \(from) – \(to)")
    }

    private static func monthYear(_ date: Date, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM yyyy",
                                                        options: 0,
                                                        locale: Locale(identifier: locale))
        return formatter.string(from: date)
    }
}
