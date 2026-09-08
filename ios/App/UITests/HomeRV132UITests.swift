import XCTest

// MARK: - RV.132 a "Check for rates" tap must show what it did

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
///
/// The reported defect: a "Check for rates" tap was indistinguishable from a
/// dead button - filled rows, an empty provider answer, a Low Power deferral,
/// nothing pending and a dead network all left the screen exactly as it was.
/// The second half of the row makes each outcome render a different state:
/// the footnote itself acknowledges the tap immediately ("Checking for rates…")
/// while the demand is on the wire, and the drain posts a toast for the
/// transient results (filled / nothing pending). The dead end stays the
/// footnote's own standing copy (RV.111), offline stays a silent non-event,
/// and the AUTOMATIC launch pass still posts nothing (S8). The surface split
/// is recorded in docs/ERRORS.md -> Home.
@MainActor
extension HomeUITests {

    /// The immediate acknowledgement (the reported symptom's direct fix): the
    /// busy line must render the moment the tap lands, BEFORE the network
    /// resolves. A slow provider (`-stubRatesSlowEcho` delays the answer by
    /// 2.5 s) is exactly where a late-only acknowledgement would read as a
    /// dead button; asserting the acknowledgement exists while the response is
    /// still pending proves the ordering. The demand then completes (echo
    /// fills the 2015 rows), so the same test also sees the outcome land.
    func testRV132AcknowledgementAppearsBeforeTheResponseResolves() {
        let app = launch(args: ["-seedHomeRV111OldPending", "-stubRatesSlowEcho"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15),
                      "the F9 footnote is present before the check")
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))

        check.tap()

        let checking = app.staticTexts["homePendingRatesFootnoteChecking"]
        XCTAssertTrue(checking.waitForExistence(timeout: 2),
                      "the tap must be acknowledged immediately, before the provider answers")

        // The demand completes: the delayed echo fills the old rows and the
        // footnote drains. 2.5 s delay + drain overhead - well inside 15 s.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.staticTexts["2 entries converted"].waitForExistence(timeout: 5),
                      "the resolved demand reports the fill it actually did")
    }

    /// Filled outcome: a demand that converts rows posts a toast NAMING the
    /// outcome ("2 entries converted") - asserting the text, never merely that
    /// a toast appeared (a toast for the wrong outcome is the vacuous trap this
    /// row names). The footnote drains as the standing state.
    func testRV132FilledOutcomePostsTheConvertedToast() {
        let app = launch(args: ["-seedHomeRV111OldPending", "-stubRatesEcho"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15))
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()

        let toast = app.staticTexts["2 entries converted"]
        XCTAssertTrue(toast.waitForExistence(timeout: 15),
                      "a demand that filled rows must name the count, not stay silent")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.staticTexts["homePendingRatesFootnoteManualRate"].exists,
                       "a fill is not the dead end - no manual-rate copy")
        XCTAssertFalse(app.staticTexts["Rates are up to date"].exists,
                       "the filled outcome must not be worded as 'nothing to check'")
    }

    /// Provider had none: an empty demand over old dates is RV.111's dead end,
    /// and it renders as the footnote's standing manual-rate copy - NOT a toast,
    /// and NOT another promise that a check will help. This is the
    /// distinguishable state for "asked and the provider had nothing".
    func testRV132ProviderHadNoneIsTheDeadEndFootnoteNotAToast() {
        let app = launch(args: ["-seedHomeRV111OldPending", "-stubRatesEmpty"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15))
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()

        let deadEnd = app.staticTexts["homePendingRatesFootnoteManualRate"]
        XCTAssertTrue(deadEnd.waitForExistence(timeout: 15),
                      "an empty demand must flip the footnote to the manual-rate copy")
        XCTAssertFalse(app.buttons["homePendingRatesFootnoteCheckButton"].exists,
                       "the dead end must not promise another check")
        XCTAssertFalse(app.staticTexts["2 entries converted"].exists,
                       "nothing filled - no converted toast")
        XCTAssertFalse(app.staticTexts["Rates are up to date"].exists,
                       "the provider was asked and had none - not 'nothing to check'")
        XCTAssertFalse(app.buttons["deltaToast"].exists,
                       "the dead end carries itself through the footnote, never a toast")
    }

    /// Nothing pending: a drain that finds no rate-pending row reports it as
    /// its OWN outcome - it is not "asked and answered empty" and not a fill.
    /// Driven through `-runRateDemandDrain` (the real `drainPendingRows` a tap
    /// runs) over a fully-converted history: no request can be made, so the
    /// drain's nothing-pending branch is what renders.
    func testRV132NothingPendingOutcomePostsItsOwnToast() {
        let app = launch(args: ["-seedHomeFullHistory", "-runRateDemandDrain"])

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["homePendingRatesFootnote"].exists,
                       "the seeded history has nothing rate-pending")

        let toast = app.staticTexts["Rates are up to date"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10),
                      "a drain with nothing pending must say so, distinctly from a fill")
        XCTAssertFalse(app.staticTexts["2 entries converted"].exists,
                       "'nothing pending' must not be worded as a conversion")
    }

    /// The automatic launch pass stays silent (S8) even though a user-initiated
    /// drain now toasts: an automatic fill that resolves pending rows must not
    /// raise the converted toast, the "up to date" toast or any delta toast.
    func testRV132AutomaticPassStillPostsNothing() {
        // RV.106's in-window pending rows: the launch's own rolling refresh
        // (echo answers it) fills them automatically - no tap, no hook.
        let app = launch(args: ["-seedHomeRV106Pending", "-stubRatesEcho"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 15)

        // The fill happened; give any (wrong) toast its full 4 s visibility and
        // assert nothing rates-shaped or delta-shaped ever appears.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            XCTAssertFalse(app.buttons["deltaToast"].exists,
                           "an automatic fill must never raise a toast (S8)")
            XCTAssertFalse(app.staticTexts["Rates are up to date"].exists)
            XCTAssertFalse(app.staticTexts["2 entries converted"].exists)
            XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                          "an automatic fill must never raise an alert (S8)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    /// The Low Power half of the row, at the surface: a "Check for rates" tap
    /// under Low Power Mode is user-initiated work, so it must RUN and report
    /// its outcome - never defer into the silence the production logs showed.
    /// (The policy assertion is L1 in `LowPowerModeTests`; this is the same
    /// guarantee rendered.) The automatic pass defers under the forced mode and
    /// posts nothing - which the earlier assertions in this method rely on the
    /// seeded launch to leave alone.
    func testRV132TapWhileLowPowerModeIsOnRunsAndReportsItsOutcome() {
        let app = launch(args: ["-seedHomeRV111OldPending", "-stubRatesEcho",
                                "-forceLowPower"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 15),
                      "rows stay pending: the automatic pass deferred under Low Power Mode")
        let check = app.buttons["homePendingRatesFootnoteCheckButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))

        check.tap()

        let toast = app.staticTexts["2 entries converted"]
        XCTAssertTrue(toast.waitForExistence(timeout: 15),
                      "a user-initiated check must run while the mode is on - not defer silently")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: footnote)
        waitForExpectations(timeout: 10)
    }
}
