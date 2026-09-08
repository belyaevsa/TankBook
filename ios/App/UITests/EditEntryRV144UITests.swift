import XCTest

// MARK: - RV.144 an entry edit re-homes to the car's CURRENT home currency

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling). The L4 the row exists for: editing a fill
/// whose money pair still records the OLD home currency (EUR, stamped when the
/// import wrote it) to the car's CURRENT home currency (PLN) resolves the row
/// at rate 1 before the sheet closes - no rate, no network, nothing left for a
/// later S8 backfill to do. The broken build leaves the row rate-pending (or,
/// after a stale-direction backfill, converted into EUR), so the log read
/// below is the assertion, not the save.
@MainActor
extension EditEntryUITests {

    func testRV144CurrencyEditToTheHomeResolvesTheRowAtRateOne() {
        let app = XCUIApplication()
        // Signed in deterministically (`-seedSettingsSignedIn`): the LOG layout
        // only renders with a session - the no-session launch is the guest
        // Home, which has no log rows (PJ.3). The Keychain survives
        // `-homeResetDatabase`, so without this the test is order-dependent on
        // whatever session a previous suite left behind. Language pinned like
        // the Home suite, so a prior RU run cannot leak in.
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-seedHomeRV144Edit"]
        app.launch()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        // The newest fill (2026-08-28) is the import-era row whose money pair
        // still homes to EUR on a car whose Garage home is now PLN.
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        // EUR != home PLN, so the currency section is open with its chips.
        let plnChip = app.buttons["manualFillUpCurrency_PLN"]
        XCTAssertTrue(plnChip.waitForExistence(timeout: 5),
                      "editing a foreign row must offer the currency chips")
        plnChip.tap()

        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Home again: the edit resolved at commit. The row must read in the
        // car's PLN home - never the stale EUR, and never rate-pending.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "homeEntryAmountPending").count, 0,
                       "a same-currency edit resolves at commit; no row may stay rate-pending")
        let amounts = app.staticTexts.matching(identifier: "homeEntryAmount")
        XCTAssertEqual(amounts.count, 2,
                       "both seeded rows must now carry a resolved home figure")
        XCTAssertTrue(amounts.allElementsBoundByIndex.allSatisfy { $0.label.contains("zł") },
                      "both rows must read in the car's PLN home, never EUR: "
                      + "\(amounts.allElementsBoundByIndex.map(\.label))")
    }
}
