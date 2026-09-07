import XCTest

// MARK: - RV.103 the Log must offer a way past the newest 20 rows

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
@MainActor
extension HomeUITests {

    /// A car with more than 20 entries must offer the load-more affordance, and
    /// using it must reveal a SPECIFIC previously hidden row - never asserted
    /// by a count, because a page that silently drops an entry counts the same
    /// as one that does not (RV.103's named trap). The seed's hidden month is
    /// the oldest one, whose every fill is at the unique "Puma" station, so the
    /// assertion is "a Puma row renders after the tap", not "some row appears".
    ///
    /// The pre-state is asserted the same way: the Puma rows must not render at
    /// all before the reveal (not merely sit below the fold - the log is a
    /// non-lazy list, so a rendered-but-below-fold row WOULD exist).
    func testLogWithHiddenHistoryRevealSurfacesTheSpecificHiddenRow() {
        let app = launch(args: ["-seedHomeRV103Reveal"])

        let pumaRows = app.buttons.matching(identifier: "logEntryButton")
            .matching(NSPredicate(format: "label CONTAINS %@", "Puma"))
        XCTAssertEqual(pumaRows.count, 0,
                       "before the reveal the hidden month must not render at all")

        let reveal = app.buttons["homeLogOlderButton"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10),
                      "a car whose history outgrows the preview must offer the reveal")
        // Hard rule 7: the affordance states how much is still hidden - the
        // seeded history hides exactly the one oldest month (four fills).
        XCTAssertTrue(reveal.label.contains("4 older entries"),
                      "the affordance must state the real hidden count, got '\(reveal.label)'")

        scrollUntilHittable(app, reveal)
        reveal.tap()

        XCTAssertTrue(pumaRows.firstMatch.waitForExistence(timeout: 5),
                      "the reveal must surface the previously hidden Puma rows")
        XCTAssertEqual(pumaRows.count, 4,
                       "all four fills of the revealed month must render")

        // One tap revealed the whole remaining month, so nothing is hidden and
        // the affordance retires itself (it is not a decorative footer).
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: reveal)
        waitForExpectations(timeout: 5)
    }

    /// The complement: a history that FITS the preview (fewer than `previewLimit`
    /// rows across its whole months) must not offer the reveal - an end of the
    /// log that IS the end of the data has nothing to say (hard rule 7).
    func testLogThatFitsThePreviewOffersNoReveal() {
        let app = launch(args: ["-seedHomeFullHistory"])

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["homeLogOlderButton"].exists,
                       "a short log must not render a load-more door")
    }

    // MARK: - Helpers

    /// Brings a log element that exists but sits below the fold to a tappable
    /// position. The log is the last block on Home, so a bounded number of
    /// upward swipes always reaches its end.
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) {
        let scrollView = app.scrollViews.firstMatch
        var attempts = 0
        while attempts < 14 && !element.isHittable {
            scrollView.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable,
                      "the reveal button never became reachable after \(attempts) swipes")
    }
}
