import XCTest

/// RV.152 - changing a car's home currency asks what to do with the log it
/// already has. The question is asked BEFORE the vehicle write, only when the
/// currency actually changed AND the car has entries; the prompt states the
/// pending count upfront. These tests drive the real Vehicle-detail save path.
@MainActor
final class RV152VehicleCurrencyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A session is required (the guest Home has no `carSwitcherButton`), and
    /// each test plants its own seed. The language is pinned EN so the button
    /// labels and the pending phrase are the English keys.
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", seed,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func openDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.buttons["garageCarRow"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
    }

    /// The options live in the menu's own collection view; the row's current
    /// value is a same-labelled button, so a same-currency pick must be scoped
    /// to the menu (a plain `app.buttons[label]` is ambiguous when the pick IS
    /// the current value).
    private func chooseCurrency(_ app: XCUIApplication, label: String) {
        let menu = app.buttons["vehicleDetailHomeCurrencyMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let option = app.collectionViews.buttons[label].firstMatch
        if option.waitForExistence(timeout: 3) {
            option.tap()
            return
        }
        let fallback = app.buttons[label].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 3),
                      "the currency menu must offer \(label)")
        fallback.tap()
    }

    private func tapSave(_ app: XCUIApplication) {
        let save = app.buttons["vehicleDetailSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    private func firstInteger(in text: String) -> Int? {
        text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    // MARK: - The question is asked only when it is real

    /// The row's whole point: a currency change on a car WITH a log presents the
    /// prompt, with both answers. Before RV.152 the change saved silently.
    func testChangingCurrencyOnACarWithEntriesPresentsThePrompt() {
        let app = launch(seed: "-seedHomeRV152")
        openDetail(app)

        chooseCurrency(app, label: "USD $")
        tapSave(app)

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "changing the home currency on a car with a log must ask")
        XCTAssertTrue(alert.buttons["Convert the log"].exists,
                      "the prompt offers 'Convert the log'")
        XCTAssertTrue(alert.buttons["Keep the entries as they are"].exists,
                      "the prompt offers 'Keep the entries as they are'")
    }

    /// An empty log has nothing to restate: no prompt, the save just lands.
    func testChangingCurrencyOnAnEmptyCarDoesNotAsk() {
        let app = launch(seed: "-seedHomeEmptyVehicle")
        openDetail(app)

        chooseCurrency(app, label: "USD $")
        tapSave(app)

        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "an empty car must not be asked about a log it does not have")
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the save must land and dismiss back to the Garage")
    }

    /// Re-picking the same currency is not a change: no prompt.
    func testRepickingTheSameCurrencyDoesNotAsk() {
        let app = launch(seed: "-seedHomeRV152")
        openDetail(app)

        chooseCurrency(app, label: "EUR €")
        tapSave(app)

        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "re-picking the same currency must not ask")
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the save must land and dismiss back to the Garage")
    }

    // MARK: - The prompt states the pending count upfront

    /// The prompt states how many rows will go pending BEFORE the user commits,
    /// and that number must be the convert's own outcome. The oracle is the
    /// app's own post-convert F9 footnote count (the same date-scoped lookup),
    /// never a second count written here.
    func testPromptPendingCountMatchesTheConvertOutcome() {
        let app = launch(seed: "-seedHomeRV152")
        openDetail(app)

        chooseCurrency(app, label: "USD $")
        tapSave(app)

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let message = alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "no rate")).firstMatch
        XCTAssertTrue(message.exists,
                      "the prompt must state the pending count upfront")
        let promptCount = firstInteger(in: message.label)
        XCTAssertNotNil(promptCount, "the prompt must carry a count; got '\(message.label)'")

        alert.buttons["Convert the log"].tap()

        // The convert ran: the Log's F9 footnote counts the rows the convert
        // could not resolve. Its number is the same lookup's outcome.
        XCTAssertTrue(app.buttons["tabbar.log"].waitForExistence(timeout: 5))
        app.buttons["tabbar.log"].tap()
        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 5),
                      "the partial convert must leave a pending row the footnote counts")
        let footnoteCount = firstInteger(in: footnote.label)
        XCTAssertEqual(promptCount, footnoteCount,
                       "the prompt's count must equal what the convert actually left pending")
        XCTAssertGreaterThan(promptCount ?? 0, 0)
    }
}
