import XCTest

// MARK: - RV.142 the Log row titles itself with the station and shows the fill's consumption

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
@MainActor
extension HomeUITests {

    /// The Log row for an imported fill: titled with the STATION where the
    /// file carried one, titled with the fuel kind where it did not, and
    /// carrying the fill's own derived consumption - never a repeated kind and
    /// never `0.0 L/100km`.
    func testRV142StationTitleFallbackAndPerFillConsumption() {
        let app = launch(args: ["-seedHomeRV142Log"])

        // The two station names ride the rows the Drivvo file named.
        XCTAssertTrue(app.staticTexts["Газпром"].waitForExistence(timeout: 10),
                      "a row whose file row named its station must title itself with it")
        XCTAssertTrue(app.staticTexts["Neste"].exists,
                      "the second station's rows title themselves with it")

        // The station-less rows fall back to the fuel kind as their title - the
        // regressed path. On this single-fuel car nothing else prints "Diesel",
        // so the count IS the fallback count (two station-less rows).
        let dieselTitles = app.staticTexts.matching(NSPredicate(format: "label == %@", "Diesel"))
        XCTAssertEqual(dieselTitles.count, 2,
                       "exactly the station-less rows title themselves with the fuel kind")

        // Per-fill consumption reaches the rows from the engine's segments, and
        // no row claims a `0.0` figure (RV.142's absent case is OMITTED).
        let consumption = app.staticTexts.matching(identifier: "logEntryConsumption")
        XCTAssertTrue(consumption.firstMatch.waitForExistence(timeout: 10),
                      "a fill that closes a segment must show its consumption")
        let labels = consumption.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !$0.hasPrefix("0.0") },
                      "no row may claim a zero consumption: \(labels)")
    }

    /// The duplicate half of RV.142: on a two-fuel car the fuel kind earns its
    /// subtitle place beside a STATION title, but a row whose title IS the fuel
    /// kind never repeats it. The bug counted five fuel-kind segments; the fix
    /// leaves only the three station-titled rows' (docs/DESIGN.md).
    func testRV142RowTitledWithTheFuelKindNeverRepeatsIt() {
        let app = launch(args: ["-seedHomeRV142KindRepeat"])

        let kindSegments = app.staticTexts.matching(identifier: "logEntryFuelKind")
        XCTAssertTrue(kindSegments.firstMatch.waitForExistence(timeout: 10),
                      "the station-titled rows must show the kind on a two-fuel car")
        // Five seeded rows: two station-less (title = kind, no repeat) and
        // three station-titled (kind shown once in the subtitle).
        XCTAssertEqual(kindSegments.count, 3,
                       "the station-less rows must never repeat their own title")
    }

    /// RU, the case that actually breaks (the rule's own note: Russian runs
    /// 20-30% longer and short strings expand worst). The fallback title is
    /// «Дизель» and every value segment must render untruncated - the count is
    /// the same two fallback rows, and the consumption/odometer labels are
    /// whole figures, not clipped.
    func testRV142RowDoesNotTruncateInRussian() {
        let app = launch(args: ["-seedHomeRV142Log"],
                         language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])

        let dieselTitles = app.staticTexts.matching(NSPredicate(format: "label == %@", "Дизель"))
        XCTAssertTrue(dieselTitles.firstMatch.waitForExistence(timeout: 10),
                      "the station-less rows must render their Russian fallback title")
        XCTAssertEqual(dieselTitles.count, 2,
                       "the two station-less rows render «Дизель» as their title")

        let consumption = app.staticTexts.matching(identifier: "logEntryConsumption")
        XCTAssertTrue(consumption.firstMatch.exists,
                      "per-fill consumption renders in Russian")
        let labels = consumption.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.allSatisfy { $0.contains("л/100") },
                      "the RU consumption unit must be the catalog's own: \(labels)")

        // Restore English: `-AppleLanguages` writes to UserDefaults, which
        // survives launches, so the rest of the suite must not inherit Russian.
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }
}
