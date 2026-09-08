import XCTest

// MARK: - RV.140 the Log shows the ORIGINAL amount on a rate-pending row

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
@MainActor
extension HomeUITests {

    /// A rate-pending row's money is fully known ("45.00 USD") while its rate
    /// is not - and the Log used to render nothing at all. The row must show
    /// the ORIGINAL amount, visibly distinct from a converted row: dimmed under
    /// its own identifier, with its OWN currency's symbol - never the home
    /// symbol and never a code masquerading as one (RV.145, decided
    /// 2026-09-08: every money figure renders its currency's symbol, converted
    /// or not - the distinctness now comes from the dimming, the identifier and
    /// the divider's pending phrase, not from a three-letter code).
    func testRV140PendingRowShowsOriginalAmountDistinctFromConverted() {
        let app = launch(args: ["-seedHomePendingRates"])

        // The converted rows keep their home figure: three EUR rows, each a
        // real home amount with the euro symbol.
        let converted = app.staticTexts.matching(identifier: "homeEntryAmount")
        XCTAssertEqual(converted.count, 3,
                       "the three converted rows must keep the home-amount identifier")
        let convertedLabels = converted.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(convertedLabels.allSatisfy { $0.contains("€") },
                      "a converted row shows its home amount: \(convertedLabels)")

        // The three rate-pending rows show their ORIGINAL amounts with the
        // original currency's SYMBOL, and only they do - a distinct identifier,
        // not the converted rows'. Both converted and pending rows carry
        // symbols now; the pending state is told apart by the identifier and
        // the dimming, never by a figure that reads as code-only.
        let pending = app.staticTexts.matching(identifier: "homeEntryAmountPending")
        XCTAssertEqual(pending.count, 3,
                       "the three pending rows must render their original amount")
        let labels = pending.allElementsBoundByIndex.map(\.label).sorted()
        XCTAssertEqual(labels,
                       ["289.50\u{00A0}zł", "294.00\u{00A0}zł", "299.00\u{00A0}zł"],
                       "a pending row shows the amount as paid with its own currency's symbol")
        XCTAssertFalse(labels.contains { $0.contains("€") },
                       "an unconverted figure must never carry the home symbol: \(labels)")

        // The original amount is not a home figure, and the row says so: the
        // month divider still reports the pending month honestly.
        XCTAssertTrue(app.staticTexts["homePendingRatesFootnote"].exists,
                      "the F9 footnote still explains the pending rows")
    }
}
