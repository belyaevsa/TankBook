import XCTest

/// RV.280 - a late expense read carries the receipt's currency, so a foreign
/// figure is offered and stored with its own symbol, never as home money (hard
/// rule 3). The policy decision is L1-tested (`RV280LateExpenseCurrencyTests`);
/// this suite asserts the presentation the L1 layer cannot see - the receipt
/// side renders the read's symbol and the entry side the user's - and that
/// ticking the currency leaves the entry in the read's currency.
///
/// Seed (`InboxTestSeed`): `-seedInboxExpenseCurrency` is the saved EUR expense
/// with a PLN late read, so the two columns must show different symbols.
@MainActor
final class InboxExpenseCurrencyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase", "-skipWelcome", "-inboxReset",
            "-seedSettingsSignedIn",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"
        ] + arguments
        app.launch()
        return app
    }

    /// A foreign late read renders its own symbol on the receipt side and the
    /// entry's on the "You entered" side, and ticking the currency leaves the
    /// entry in the read's currency - never home money.
    func testAForeignExpenseReadOffersAndAppliesTheReceiptCurrency() {
        let app = launch(["-seedInboxExpenseCurrency"])
        app.buttons["inboxBellButton"].tap()

        XCTAssertTrue(app.buttons["inboxTick_currency"].waitForExistence(timeout: 5),
                      "a foreign late read must offer its currency")
        XCTAssertTrue(app.buttons["inboxTick_total"].exists,
                      "the read's amount is still offered")
        XCTAssertTrue(app.staticTexts["20.00\u{00A0}zł"].exists,
                      "the receipt's figure must render under its own symbol")
        XCTAssertTrue(app.staticTexts["12.40\u{00A0}€"].exists,
                      "the user's column stays the entry's own symbol")
        XCTAssertTrue(app.staticTexts["PLN"].exists,
                      "the currency row names the read's currency")
        XCTAssertTrue(app.staticTexts["EUR"].exists,
                      "the currency row names the entry's currency")

        // Take the currency alone: the amount stays the user's, the currency
        // becomes the read's.
        app.buttons["inboxTick_currency"].tap()
        app.buttons["inboxUpdateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "updating clears the item")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let row = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved expense must be in the log")
        row.tap()
        let chip = app.buttons["manualFillUpCurrency_PLN"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "the entry must now be in the read's currency")
        XCTAssertTrue(chip.isSelected,
                      "the read's currency must be the entry's selected one")
    }

    /// The same foreign offer in Russian: the symbols are locale-invariant, but
    /// the currency row's label is where RU runs longest, so the offer must
    /// still be reachable and applicable under `ru`.
    func testAForeignExpenseReadOffersTheReceiptCurrencyInRussian() {
        let app = launch(["-seedInboxExpenseCurrency"], language: "ru")
        app.buttons["inboxBellButton"].tap()

        XCTAssertTrue(app.buttons["inboxTick_currency"].waitForExistence(timeout: 5),
                      "a foreign late read must offer its currency in RU too")
        XCTAssertTrue(app.staticTexts["20.00\u{00A0}zł"].exists)
        XCTAssertTrue(app.staticTexts["12.40\u{00A0}€"].exists)

        app.buttons["inboxTick_currency"].tap()
        app.buttons["inboxUpdateButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inboxEmptyState"].waitForExistence(timeout: 5),
                      "updating clears the item in RU too")
    }
}
