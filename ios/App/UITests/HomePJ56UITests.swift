import XCTest

// MARK: - PJ.56 a purchase-group header never stays silent over a divider that speaks

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
@MainActor
extension HomeUITests {

    /// RV.84's lesson, applied to a header figure: an element that EXISTS can be
    /// 86% clipped and still report `isHittable == true`. The claim here is that
    /// the phrase is ON SCREEN, so it is a frame question - the element's frame
    /// must be a real, non-empty rectangle fully inside the window.
    private func assertPhraseIsOnScreen(_ element: XCUIElement, in app: XCUIApplication,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) {
        let frame = element.frame
        XCTAssertTrue(frame.width > 0 && frame.height > 0,
                      "the element must have a real frame, not blank space",
                      file: file, line: line)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame),
                      "the phrase must be on screen - its frame \(frame) must sit "
                      + "inside the window \(window), never clipped by it",
                      file: file, line: line)
    }

    /// A receipt whose members are ALL rate-pending (.pending) must say why its
    /// header shows no total: the divider over the same members prints "N
    /// entries pending rates", and the group header one row below it must print
    /// the SAME phrase - not blank space (the PJ.56 defect).
    func testPJ56PendingGroupHeaderStatesThePendingPhraseOnScreen() {
        let app = launch(args: ["-seedHomePJ56PendingGroup"])

        let toggle = app.buttons["logGroupToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the seeded all-pending receipt must render its group card")

        // The pending phrase rides the header itself - absent, the header is the
        // empty slot PJ.56 removes. The divider's identical phrase is NOT the
        // subject here; this element is the header's own, by identifier.
        let note = app.staticTexts["logGroupPendingRates"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5),
                      "an all-pending receipt header must say why it shows no total")
        XCTAssertTrue(note.label.contains("pending rates"),
                      "the header must carry the pending phrase, got \(note.label)")
        assertPhraseIsOnScreen(note, in: app)

        // Nothing is invented in place of a figure: no bare total and no zero
        // can appear where the whole receipt is still waiting on a rate.
        XCTAssertFalse(app.staticTexts["logGroupGrandTotal"].exists,
                       "a .pending receipt has no home figure to state")
    }

    /// A receipt whose KNOWN members span home currencies (.mixed) must state
    /// its per-currency breakdown in the header - each figure under its own
    /// symbol - never one summed total and never blank space (PJ.56, hard
    /// rule 3). The header and the divider over the same members explain the
    /// receipt with the same breakdown.
    func testPJ56MixedGroupHeaderStatesTheBreakdownNotACrossCurrencyTotal() {
        let app = launch(args: ["-seedHomePJ56MixedGroup"])

        let toggle = app.buttons["logGroupToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the seeded mixed receipt must render its group card")

        let figure = app.staticTexts["logGroupGrandTotal"].firstMatch
        XCTAssertTrue(figure.waitForExistence(timeout: 5),
                      "a mixed receipt header must state its breakdown, not blank space")
        XCTAssertTrue(figure.label.contains("€") && figure.label.contains("$"),
                      "the breakdown pairs each figure with its own currency, got \(figure.label)")
        XCTAssertFalse(figure.label.contains("99.02"),
                       "the header must never print the cross-currency sum, got \(figure.label)")
        assertPhraseIsOnScreen(figure, in: app)

        // A mixed month whose every member HAS converted is fully stated, so
        // nothing is waiting and the pending phrase must not appear at all.
        // The group header's `groupPendingNote` guarded this from the start;
        // the month divider's own `pendingNote` did not, and printed
        // "0 entries pending rates" beneath a complete breakdown - visible only
        // in the committed screenshot, because this seed renders the first
        // `.mixed` month the app has ever produced.
        let divider = app.staticTexts["logMonthDivider"].firstMatch
        XCTAssertTrue(divider.waitForExistence(timeout: 5), "the month divider renders")
        XCTAssertFalse(divider.label.contains("0 entries pending rates"),
                       "a fully converted mixed month states no pending count, got "
                           + "'\(divider.label)'")
        XCTAssertFalse(app.staticTexts["logGroupPendingRates"].exists,
                       "nor does its group header")
    }
}
