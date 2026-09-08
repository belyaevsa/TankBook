import XCTest

// MARK: - RV.145 a euro sum never carries a dollar sign; a mixed month shows a breakdown

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
///
/// The owner's 2026-09-08 screenshot: the AUGUST divider read `91 $` above rows
/// of `36.06 €`, `28.78 €` and `26.59 €` (36.06 + 28.78 + 26.59 = 91.43) on a
/// car whose Garage home currency is USD. Two mechanisms fed it - the divider
/// stamped the VEHICLE's symbol on a sum of rows homed in another currency, and
/// the accumulator summed `homeAmount`s without reading `homeCurrency`. Both
/// are asserted here at the rendered surface, where the defect was visible.
@MainActor
extension HomeUITests {

    /// The owner's exact scene: a USD car whose current rows are EUR-homed
    /// (converted while the car's home was EUR - the stamp survives the Garage
    /// change) beside rate-pending PLN rows. No converted row may carry `$`,
    /// and the month divider and the vitals tile must state the euro sum in
    /// euros. This is the case that failed today.
    func testRV145EuroRowsOnAUSDCarNeverCarryTheDollarSign() {
        let app = launch(args: ["-seedHomeRV145Owner"])

        let converted = app.staticTexts.matching(identifier: "homeEntryAmount")
        XCTAssertTrue(converted.firstMatch.waitForExistence(timeout: 15),
                      "the EUR-homed rows must render their amounts")
        let rowLabels = converted.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(rowLabels.allSatisfy { $0.contains("€") },
                      "every converted row is EUR-homed and must show the euro: \(rowLabels)")
        XCTAssertFalse(rowLabels.contains { $0.contains("$") },
                       "a euro figure must never carry the car's dollar: \(rowLabels)")

        // The month divider states the euro sum in euros - never `91 $`.
        let dividerLabels = app.descendants(matching: .any)
            .matching(identifier: "logMonthDivider")
            .allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(dividerLabels.contains { $0.contains("€") },
                      "the divider must state the euro sum, got \(dividerLabels)")
        XCTAssertFalse(dividerLabels.contains { $0.contains("$") },
                       "no divider may print a dollar figure for a euro month: \(dividerLabels)")

        // The current-month vitals tile inherits the same fix: its value line
        // is the staticText carrying the identifier whose label holds the
        // figure (the title and caption are sibling elements under the same id).
        let tileValue = app.staticTexts.matching(identifier: "homeMonthSpendTile")
            .matching(NSPredicate(format: "label CONTAINS %@", "€")).firstMatch
        XCTAssertTrue(tileValue.waitForExistence(timeout: 10),
                      "the seeded month is current, so the spend tile must render")
        XCTAssertFalse(tileValue.label.contains("$"),
                       "the vitals tile may not carry the car's dollar on a euro month: \(tileValue.label)")
    }

    /// A month whose KNOWN figures span two home currencies (EUR rows beside a
    /// USD row) cannot state one number: the divider and the vitals tile must
    /// show the per-currency breakdown, each figure with its own symbol - the
    /// displayed decision docs/ERRORS.md -> Home records for the mixed case.
    func testRV145MixedCurrencyMonthRendersThePerCurrencyBreakdown() {
        let app = launch(args: ["-seedHomeRV145Mixed"])

        XCTAssertTrue(app.staticTexts.matching(identifier: "homeEntryAmount")
            .firstMatch.waitForExistence(timeout: 15))

        // The mixed month's figures: euro rows and a dollar row each render
        // with their own currency's symbol.
        let rowLabels = app.staticTexts.matching(identifier: "homeEntryAmount")
            .allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(rowLabels.contains { $0.contains("€") },
                      "the EUR rows must keep the euro, got \(rowLabels)")
        XCTAssertTrue(rowLabels.contains { $0.contains("$") },
                      "the USD row must carry the dollar, got \(rowLabels)")

        // The divider and the vitals tile carry BOTH currencies - the figure is
        // a breakdown, never a single bare number.
        let dividerLabels = app.descendants(matching: .any)
            .matching(identifier: "logMonthDivider")
            .allElementsBoundByIndex.map(\.label)
        let newestDivider = dividerLabels.first ?? ""
        XCTAssertTrue(newestDivider.contains("€") && newestDivider.contains("$"),
                      "the mixed month's divider must show both currencies, got \(newestDivider)")

        let tileValue = app.staticTexts.matching(identifier: "homeMonthSpendTile")
            .matching(NSPredicate(format: "label CONTAINS %@", "$")).firstMatch
        XCTAssertTrue(tileValue.waitForExistence(timeout: 10))
        XCTAssertTrue(tileValue.label.contains("€") && tileValue.label.contains("$"),
                      "the spend tile must render the per-currency breakdown, got \(tileValue.label)")
    }
}
