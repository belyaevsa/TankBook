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

        // RV.263: a file with no currency column must not commit a GUESS, so
        // confirm is disabled until the question is answered (F6).
        XCTAssertFalse(app.buttons["importConfirmButton"].isEnabled,
                       "a no-column file must not commit a guessed currency")

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
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "answering the currency question enables confirm")
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

    /// RV.263 - a currency the file DECLARES is a default the user can correct,
    /// never a fact (hard rule 13, hard rule 3). The MFM fixture declares USD on
    /// every row, so the currency card must render PRE-FILLED with USD (not the
    /// car's EUR), and a different pick must re-home every row - visible in the
    /// total spend. Before this row the card did not render at all for a declared
    /// currency, so the wrong currency imported with no fix.
    func testDeclaredCurrencyRendersAsAnEditablePicker() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.otherElements["importCurrencyQuestion"].waitForExistence(timeout: 5),
                      "a file that declares a currency must still offer it for correction")
        let picker = app.buttons["importCurrencyPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the declared currency is an editable picker")
        XCTAssertTrue(picker.label.contains("USD"),
                      "the picker is pre-filled with the DECLARED currency, was '\(picker.label)'")

        let total = app.descendants(matching: .any)["importPreviewTotalSpend"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the total spend renders")
        XCTAssertTrue(total.label.contains("$"),
                       "the declared currency reaches the total spend, was '\(total.label)'")

        picker.tap()
        let rub = app.buttons["importCurrencyOption-RUB"]
        XCTAssertTrue(rub.waitForExistence(timeout: 5), "the RUB option never appeared")
        rub.tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("₽"),
                       "the corrected currency reaches every row, was '\(total.label)'")
    }

    /// RV.263, RU: the declared-currency card and its copy render in Russian -
    /// the subtitle names the code the file carries, and the picker is still the
    /// declared currency. RU is where the composed sentence runs longest.
    func testDeclaredCurrencyRendersAsAnEditablePickerInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.otherElements["importCurrencyQuestion"].waitForExistence(timeout: 5),
                      "a file that declares a currency must still offer it for correction")
        XCTAssertTrue(app.staticTexts["В файле указано: USD. Измените, если это не так."].exists,
                      "the RU subtitle names the declared currency")
        let picker = app.buttons["importCurrencyPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the declared currency is an editable picker")
        XCTAssertTrue(picker.label.contains("USD"),
                      "the picker is pre-filled with the DECLARED currency, was '\(picker.label)'")

        let total = app.descendants(matching: .any)["importPreviewTotalSpend"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the total spend renders")
        XCTAssertTrue(total.label.contains("$"),
                       "the declared currency reaches the total spend, was '\(total.label)'")
    }
}
