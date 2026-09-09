import XCTest

// MARK: - RV.146 the currency offer adapts to the car and the device

/// The chip row is no longer a hardcoded four: it leads with the car's home
/// currency, then offers the device region's currency (docs/SCHEMA.md ->
/// Currency offer), and it CAPS at what fits instead of truncating a label or
/// overflowing. The caps are asserted by GEOMETRY, never text - a clipped chip
/// still reports its full label to the accessibility tree (the vacuous trap).
@MainActor
extension ConfirmManualUITests {

    private var chipPredicate: NSPredicate {
        NSPredicate(format: "identifier BEGINSWITH %@", "manualFillUpCurrency_")
    }

    /// Expand the currency section on the seeded EUR car and scroll its chips
    /// clear of the pinned save bar.
    private func openCurrencyChips(_ app: XCUIApplication) {
        openManualForm(app)
        let collapsed = app.buttons["manualFillUpCurrencyCollapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 5))
        scrollClearOfSaveBar(app, collapsed)
        collapsed.tap()
        let home = app.buttons["manualFillUpCurrency_EUR"]
        XCTAssertTrue(home.waitForExistence(timeout: 5),
                      "the seeded car's home currency must lead the chip row")
        scrollClearOfSaveBar(app, home)
    }

    /// The visible chips in visual order, plus the "More…" button.
    private func currencyRowElements(_ app: XCUIApplication)
        -> (chips: [XCUIElement], more: XCUIElement) {
        let chips = app.buttons.matching(chipPredicate).allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
        let more = app.buttons["currencyChipMore"]
        return (chips, more)
    }

    /// The seeded car is EUR-home and the row is fresh (no history), so under
    /// the en_US region the row must lead EUR then USD - proof the list
    /// actually adapts, never a hardcoded second literal.
    func testCurrencyRowLeadsHomeThenTheDeviceRegion() {
        let app = launch(args: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        openCurrencyChips(app)
        let (chips, _) = currencyRowElements(app)
        XCTAssertGreaterThanOrEqual(chips.count, 2,
                                    "the row must offer the region's currency after home")
        XCTAssertEqual(chips[0].identifier, "manualFillUpCurrency_EUR",
                       "the car's home currency must be first, got \(chips.map(\.identifier))")
        XCTAssertEqual(chips[1].identifier, "manualFillUpCurrency_USD",
                       "the device region's currency must follow home, got \(chips.map(\.identifier))")
    }

    /// Every visible chip plus "More…" stays on ONE row inside the window at
    /// the largest Dynamic Type size - the row caps instead of truncating or
    /// running off-screen. English.
    func testCurrencyRowFitsAtLargestTextSizeEnglish() {
        let app = launch(args: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"])
        openCurrencyChips(app)
        assertRowFitsOnOneLineInsideTheWindow(app)
    }

    /// The same at XXXL in Russian (RU copy runs longer; the shorter row must
    /// still never clip).
    func testCurrencyRowFitsAtLargestTextSizeRussian() {
        let app = launch(args: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"])
        openCurrencyChips(app)
        assertRowFitsOnOneLineInsideTheWindow(app)
        // Restore the app's persisted language for suites running after this one.
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    /// The cap contract: at least the home chip renders, every visible chip and
    /// "More…" shares one row (the cap never wraps), and every element's frame
    /// lies inside the window (nothing runs off-screen).
    private func assertRowFitsOnOneLineInsideTheWindow(_ app: XCUIApplication) {
        let (chips, more) = currencyRowElements(app)
        XCTAssertGreaterThanOrEqual(chips.count, 1,
                                    "the row must cap, never empty itself")
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        scrollClearOfSaveBar(app, more)

        let window = app.windows.firstMatch.frame
        let elements = chips + [more]
        let ys = elements.map { $0.frame.minY }
        let rowTop = ys.min() ?? 0
        let rowBottom = ys.max() ?? 0
        XCTAssertLessThanOrEqual(rowBottom - rowTop, 1.0,
                                 "all chips and More… must sit on one row")
        for element in elements {
            XCTAssertGreaterThanOrEqual(element.frame.maxX, 0)
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX,
                                     "\(element.identifier) runs off-screen at XXXL")
            XCTAssertLessThanOrEqual(element.frame.minX, window.maxX)
        }
    }
}
