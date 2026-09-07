import XCTest

// RV.113 - a file with no currency column must ASK (L4). A Drivvo export carries
// amounts but no currency, so the wizard offers the destination car's home
// currency as the default the user can change (hard rule 13, hard rule 3). The
// question is asked once per file, and the answer reaches every row that will
// commit - the total-spend figure is derived from exactly those rows, so a
// currency in it proves the answer reached them.
//
// The parse itself runs server-side (hard rule 9's named exception), so L4
// drives a stub of what the server returns for a no-currency Drivvo file: empty
// candidate currencies and a `currency` ambiguity with EMPTY options. The
// vacuous trap this suite exists to avoid is defaulting the currency silently
// to the car's and never asking - so the assertion is that the question renders
// (once) and that a changed answer moves the derived spend figure.
//
// The suite lives in its own file so `ImportUITests.swift` stays under the
// SwiftLint file-length ceiling.

@MainActor
final class ImportCurrencyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    func testCurrencyQuestionAsksOnceAndTheAnswerReachesEveryRow() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCurrency"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        let question = app.otherElements["importCurrencyQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5),
                      "the currency question renders on the preview")
        XCTAssertEqual(app.otherElements.matching(identifier: "importCurrencyQuestion").count, 1,
                       "the question is asked once per file, never per row")

        // The default is the car's home currency (EUR for the seeded Volvo), and
        // it already reaches the total spend before any answer.
        let total = app.descendants(matching: .any)["importPreviewTotalSpend"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the total spend renders")
        XCTAssertTrue(total.label.contains("€"),
                       "the default (the car's home currency) reaches the total spend, was '\(total.label)'")

        // Change to RUB: the answer applies to every row, so the total spend
        // re-renders in ₽.
        app.buttons["importCurrencyPicker"].tap()
        let rub = app.buttons["importCurrencyOption-RUB"]
        XCTAssertTrue(rub.waitForExistence(timeout: 5), "the RUB option never appeared")
        rub.tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("₽"),
                       "the answered currency reaches every row, was '\(total.label)'")

        app.buttons["importConfirmButton"].tap()
        // The commit writes the rows and dismisses the wizard - the preview
        // leaves the tree only after `confirmImport` returns success.
        let preview = app.otherElements["importPreviewScreen"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: preview)
        waitForExpectations(timeout: 10)
    }
}
