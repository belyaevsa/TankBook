import XCTest

// MARK: - RV.112 the vitals tile must never report a rate-pending month as zero

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
///
/// RV.106 fixed the Log's month divider and stopped there; the current-month
/// spend TILE still summed a rate-pending row as zero, so a month whose rows
/// carry no home figure yet rendered `0 €` directly above them (RV.140's
/// screenshot: «РАСХОДЫ ЗА СЕНТЯБРЬ 0 €» over two `110.00 USD` rows). The tile
/// now speaks the divider's language: a fully-pending month prints NO number at
/// all - the tile is absent, and the F9 footnote on the log below says why.
@MainActor
extension HomeUITests {

    /// `-seedHomeRV88USDPending` puts two current-month foreign rows (110.00
    /// USD each) on a EUR car with no rate on the device - the exact owner
    /// shape. `monthSpend` classifies the month `.pending`, so the vitals tile
    /// must NOT render a figure (a `0 €` slot is the defect) and the divider +
    /// footnote must carry the pending phrase instead.
    func testRV112PendingCurrentMonthTileNeverPrintsZeroEuro() {
        let app = launch(args: ["-seedHomeRV88USDPending"])

        // The month has entries, so this is a genuinely-pending tile, not a
        // no-entries omission - and it must be ABSENT rather than a bare `0 €`.
        let spendTile = app.staticTexts["homeMonthSpendTile"]
        XCTAssertFalse(spendTile.exists,
                       "a fully-pending month must not print a number on the vitals tile")
        XCTAssertFalse(app.staticTexts["0 €"].exists,
                       "a pending month must never render a `0 €` anywhere on Home")

        // The F9 footnote (the count) and the pending divider say why instead.
        XCTAssertTrue(app.staticTexts["homePendingRatesFootnote"].waitForExistence(timeout: 15),
                      "the pending count footnote must explain the absent figure")
        let dividerLabels = app.descendants(matching: .any)
            .matching(identifier: "logMonthDivider")
            .allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(dividerLabels.contains { $0.contains("entries pending rates") },
                      "the current month's divider must carry the pending phrase, got \(dividerLabels)")
        XCTAssertFalse(dividerLabels.contains { $0.contains("0 €") },
                       "no divider may read `0 €` beside rows that carry no home amount")
    }
}
