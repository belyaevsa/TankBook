import XCTest

// MARK: - RV.111 a pending row older than the rolling rate window is never re-asked

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
///
/// RV.106 proved the footnote's "Check for rates" fills rows whose dates sit
/// INSIDE the rolling 400-day pack window - the owner's June-to-September
/// import. This row is the case RV.106's seed cannot reach: a pending row
/// dated YEARS back (a multi-year import committed while the archive was still
/// publishing). The launch refresh is rolling-only, so nothing automatic ever
/// asks for a 2015 date; the check must DEMAND the pending rows' own span.
@MainActor
extension HomeUITests {

    /// The dead end, rendered: a demand check over old rows that the provider
    /// answers EMPTY (`-stubRatesEmpty` - reached, no rows for those dates)
    /// must flip the footnote from "Check for rates" to the manual-rate copy.
    /// The check affordance that cannot help must be GONE - never a promise
    /// that another check will.
    func testRV111OldRowsDeadEndNamesTheManualRateAfterAnEmptyDemand() {
        let app = launch(args: ["-seedHomeRV111OldPending", "-stubRatesEmpty"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15),
                      "before the check the F9 footnote is present")
        XCTAssertTrue(footnote.label.contains("2 entries pending rates"),
                      "the footnote must show the derived count, got '\(footnote.label)'")
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5),
                      "before any demand pass the footnote offers its next step")

        check.tap()

        let deadEnd = app.staticTexts["homePendingRatesFootnoteManualRate"]
        XCTAssertTrue(deadEnd.waitForExistence(timeout: 25),
                      "an empty demand over old dates must name the manual rate")
        XCTAssertTrue(app.staticTexts["homePendingRatesFootnote"].exists,
                      "the count stays while the rows are still pending")
        XCTAssertFalse(app.buttons["homePendingRatesFootnoteCheckButton"].exists,
                       "the dead end must not promise another check")
    }

    /// The row's whole point at the UI level: the check over old rows is a
    /// DEMAND fetch. Under `-stubRatesEcho` the launch refresh answers the
    /// rolling 400 days only (2015 not among them), so the rows stay pending;
    /// the tap's demand asks the 2015 span and the echo's answer fills them -
    /// the footnote drains. RV.106's equivalent test passes against a rolling-
    /// only check; this one cannot, because the rows' dates are outside it.
    func testRV111OldRowsFillWhenTheDemandEchoAnswersTheirDates() {
        let app = launch(args: ["-seedHomeRV111OldPending", "-stubRatesEcho"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15),
                      "the launch's rolling refresh cannot reach a 2015 date")
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 25)
        XCTAssertFalse(app.buttons["homePendingRatesFootnoteCheckButton"].exists,
                       "with nothing pending there is nothing to check")
    }
}
