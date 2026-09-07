import XCTest

// MARK: - RV.106 a month whose rates have not arrived must not report "0 €"

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
@MainActor
extension HomeUITests {

    /// The divider labels are the whole claim: for the owner's exact shape
    /// (a converted month beside all-pending months), the pending months'
    /// dividers must SAY why they show no figure ("N entries pending rates"),
    /// never print a bare `0 €`, and the converted month's divider must carry
    /// its real euro figure.
    private func dividerLabels(_ app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).matching(identifier: "logMonthDivider")
            .allElementsBoundByIndex.map(\.label)
    }

    func testRV106PendingMonthDividerNeverPrintsZeroEuro() {
        let app = launch(args: ["-seedHomeRV106Pending"])

        // The seeded history renders three months: August converted (the
        // owner's "rows carry amounts"), July and June all rate-pending.
        let labels = dividerLabels(app)
        XCTAssertTrue(labels.count == 3,
                      "the seed renders August + July + June dividers, got \(labels)")

        let converted = labels.first { $0.contains("August") && $0.contains("€") }
        XCTAssertNotNil(converted,
                        "the converted month must carry a real euro total, got \(labels)")

        let pending = labels.filter { $0.contains("entries pending rates") }
        XCTAssertEqual(pending.count, 2,
                       "both pending months must say why they show no figure, got \(labels)")
        for divider in pending {
            XCTAssertFalse(divider.contains("€"),
                           "a pending month must never print a euro figure: \(divider)")
            XCTAssertFalse(divider.contains("0"),
                           "a pending month must never print a zero: \(divider)")
        }
    }

    /// The footnote's next step (hard rule 7) is an ACTION that does something
    /// observable: "Check for rates" re-runs the rate refresh + S8 backfill,
    /// and the second `/rates/pack` request (`-stubRatesMissThenHit` answers
    /// the first empty - the server had not published yet) fills the pending
    /// rows. The footnote disappears and every divider carries a figure.
    func testRV106FootnoteCheckForRatesFillsThePendingRows() {
        let app = launch(args: ["-seedHomeRV106Pending", "-stubRatesMissThenHit"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15),
                      "before the check the F9 footnote is present")
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5),
                      "the footnote must offer its next step, not stop at a count")
        XCTAssertTrue(dividerLabels(app).contains { $0.contains("entries pending rates") },
                      "the pending divider is the before-state")

        check.tap()

        // Observable outcome: the second pack request serves the dates, the
        // backfill fills the rows silently (S8) and Home re-reads.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 25)
        let after = dividerLabels(app)
        XCTAssertFalse(after.contains { $0.contains("entries pending rates") },
                       "after the fill no divider says pending: \(after)")
        XCTAssertTrue(after.contains { $0.contains("August") && $0.contains("€") },
                      "the converted month's divider still carries its figure")
    }

    /// The open question this row had to measure (RV.106 brief): do rows whose
    /// rate the server had not yet published resolve on a LATER LAUNCH? The
    /// seed's pending rows (June/July 2026) sit inside the rolling 400-day pack
    /// window, so the automatic pass of a later launch re-fetches the pack and
    /// the S8 backfill fills them - asserted through the divider, the surface
    /// that used to print the false `0 €`.
    func testRV106PendingRowsResolveOnALaterLaunchOnceRatesArePublished() {
        // Phase 1: no rates anywhere (offline seeded launch). Pending holds.
        var app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-seedHomeRV106Pending"]
        app.launch()

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15),
                      "phase 1: rows stay pending while the archive lacks their dates")
        XCTAssertTrue(dividerLabels(app).contains { $0.contains("entries pending rates") })
        app.terminate()

        // Phase 2: the server has since published those dates (`-stubRatesEcho`
        // answers the rolling pack the launch refresh asks for). The launch's
        // own pass fills the rows - no button, no debug hook.
        app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-seedHomeRV106Pending", "-stubRatesEcho"]
        app.launch()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 25)
        let after = dividerLabels(app)
        XCTAssertFalse(after.contains { $0.contains("entries pending rates") },
                       "a later launch after publication fills the pending rows: \(after)")
        XCTAssertTrue(after.allSatisfy { $0.contains("€") },
                      "every divider now carries a real euro figure: \(after)")
    }
}
