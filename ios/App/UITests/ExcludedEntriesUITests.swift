import XCTest

// MARK: - RV.141 (2026-09-08): "8 entries excluded" names no entries and no reason
//         PJ.57  (2026-09-10): the excluded-count link renders like its caption

/// Kept as extensions of the Home and Trends suites (their own file, so the base
/// files stay under the lint ceiling) - the tests run as part of those suites.
///
/// RV.141 defect: the excluded-count footnote was inert text on Home, and even
/// where it was tappable (Trends) it opened ONE entry, so with N > 1 excluded
/// the rest were unreachable - and no surface said WHY an entry was out (a
/// timeline conflict is fixed by editing the odometer or the date; an unresolved
/// duplicate by Merge or Keep both). RV.141 fix: the count reaches its entries
/// from both surfaces - a single excluded entry opens directly, N > 1 opens the
/// excluded-entries list that names all N and each one's reason.
///
/// PJ.57 defect: the RV.141 footnote is a link whose pixels were identical to
/// the caption it can also render - amber is attention, never action (hard rule
/// 5), so the tappable case now carries the app's one "leads somewhere"
/// chevron, and the tests here pin that the two branches differ and that the
/// passive caption stays text alone.
@MainActor
extension HomeUITests {

    /// The headline L4, red before the fix: the Home footnote is tappable and
    /// reaches the excluded entries. `-seedHomeExcludedMix` leaves 2 entries out
    /// (an unresolved duplicate's excluded member and a conflicted fill), so the
    /// count reads "2 entries excluded" and the footnote must be a real door.
    func testRV141HomeFootnoteIsTappableAndReachesTheExcludedEntries() {
        let app = launch(args: ["-seedHomeExcludedMix"])

        let footnote = app.buttons["homeExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10),
                      "Home's excluded footnote must be a reachable button, not inert text")
        XCTAssertTrue(footnote.label.contains("2 entries excluded"),
                      "the footnote must state the engine's real count, got '\(footnote.label)'")

        // RV.84's trap: assert the door is really on screen and inside the
        // window, then that tapping ARRIVES at the entries - never isHittable
        // alone.
        scrollUntilHittable(footnote, in: app)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(footnote.frame.minX, window.minX - 1,
                                    "the footnote must start inside the window")
        XCTAssertLessThanOrEqual(footnote.frame.maxX, window.maxX + 1,
                                 "the footnote must end inside the window")

        footnote.tap()
        XCTAssertTrue(app.navigationBars["Excluded entries"].waitForExistence(timeout: 5),
                      "tapping the N > 1 count must open the list, not a single entry")
    }

    /// The population guard: with N > 1 excluded, the destination lists ALL N -
    /// the count on the destination matches the count in the footnote. This is
    /// the test that catches the trap the row was filed for: routing the count
    /// into a screen that shows fewer rows than it promised.
    func testRV141HomeExcludedListShowsEveryEntryTheFootnoteCounted() {
        let app = launch(args: ["-seedHomeExcludedMix"])

        let footnote = app.buttons["homeExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10))
        XCTAssertTrue(footnote.label.contains("2 entries excluded"),
                      "the footnote must promise exactly 2, got '\(footnote.label)'")
        scrollUntilHittable(footnote, in: app)
        footnote.tap()

        XCTAssertTrue(app.navigationBars["Excluded entries"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(identifier: "excludedEntryRow")
        XCTAssertEqual(rows.count, 2,
                       "the list the '2 entries excluded' count opened must show 2 rows, "
                           + "not the 1 a conflicts-only screen would show (RV.141 population trap)")
    }

    /// Each listed row states its reason, and a conflict and a duplicate read
    /// DIFFERENTLY - the two causes carry different fixes, which is the point of
    /// saying which one each row is.
    func testRV141HomeExcludedRowsStateReasonsThatDiffer() {
        let app = launch(args: ["-seedHomeExcludedMix"])

        let footnote = app.buttons["homeExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10))
        scrollUntilHittable(footnote, in: app)
        footnote.tap()

        XCTAssertTrue(app.navigationBars["Excluded entries"].waitForExistence(timeout: 5))
        let reasons = app.staticTexts.matching(identifier: "excludedEntryReason")
        XCTAssertEqual(reasons.count, 2,
                       "each excluded row must state why it is out")
        let labels = reasons.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("Timeline conflict") },
                      "a conflicted row must say so, got \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Possible duplicate") },
                      "a duplicate row must say so, got \(labels)")

        // A row opens the entry - the row names its next step and the tap
        // carries the user to it (hard rule 7).
        app.buttons.matching(identifier: "excludedEntryRow").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5),
                      "an excluded row must open the entry on tap")
    }

    /// Zero excluded shows no footnote at all: a clean history renders no
    /// "0 entries excluded" line (the count is derived, and nothing is wrong).
    func testRV141HomeShowsNoFootnoteWhenNothingIsExcluded() {
        let app = launch(args: ["-seedHomeFullHistory"])
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["homeExcludedFootnote"].exists,
                       "a clean history must not render an excluded footnote")
        XCTAssertFalse(app.buttons["homeExcludedFootnoteButton"].exists,
                       "a clean history must not render an excluded footnote button")
    }

    /// L4, EN at the largest text size: the footnote and the two reason rows
    /// survive Dynamic Type XL without clipping off the window's edge (a reason
    /// phrase next to a count is exactly where RU or a long label overflows).
    func testRV141ExcludedFootnoteAndReasonsFitAtXLInEnglish() {
        let app = launch(args: ["-seedHomeExcludedMix",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"])
        assertExcludedListFitsWindow(app, listTitle: "Excluded entries",
                                     conflictPhrase: "Timeline conflict",
                                     duplicatePhrase: "Possible duplicate")
    }

    /// L4, RU at the largest text size: Russian runs 20-30% longer, so the
    /// reason captions ("Конфликт в хронологии – проверьте пробег или дату")
    /// are the overflow case the EN pass cannot see.
    func testRV141ExcludedFootnoteAndReasonsFitAtXLInRussian() {
        let app = launch(args: ["-seedHomeExcludedMix",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"],
                         language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        assertExcludedListFitsWindow(app, listTitle: "Исключённые записи",
                                     conflictPhrase: "Конфликт в хронологии",
                                     duplicatePhrase: "Возможный дубликат")

        // Restore the app's persisted language: `-AppleLanguages` writes to
        // UserDefaults, which survives launches, so a suite running after this
        // RU launch must not inherit Russian (P6.13 run, 2026-08-31).
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    // MARK: - PJ.57 (2026-09-10): the link must not render like its caption

    /// L4, red before the fix: the link case is distinguishable from the passive
    /// caption by an asserted property - the trailing chevron affordance. Before
    /// PJ.57 both branches of `ExcludedEntriesFootnote.body` rendered the
    /// identical amber `.caption2` label, so no property existed that could
    /// separate a tappable footnote from the caption it replaced (only the
    /// accessibility hint differed, which a sighted user never receives). The
    /// chevron carries its own identifier, so the assertion is on the
    /// affordance itself - never "the footnote exists" or "it is tappable",
    /// both already true on the unfixed code. `-seedHomeExcludedMix` leaves 2
    /// entries out, so the footnote is a link to the excluded-entries list.
    func testPJ57LinkCaseIsDistinguishableFromThePassiveCaption() {
        let app = launch(args: ["-seedHomeExcludedMix"])

        let footnote = app.buttons["homeExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10),
                      "the link footnote must be present")
        // Exact, not contains: the button's spoken name is the count phrase and
        // nothing else - a chevron leaking into the label would fail here, the
        // same rule the Garage strip's own exact-label test pins (docs/DESIGN.md:
        // the chevron is chrome, never content).
        XCTAssertEqual(footnote.label, "2 entries excluded",
                       "the link must read as the count alone, got '\(footnote.label)'")

        let chevron = app.images["homeExcludedFootnoteChevron"]
        XCTAssertTrue(chevron.waitForExistence(timeout: 5),
                      "the link footnote must carry the chevron affordance the passive caption lacks")
    }

    /// L4: the passive caption (`destination == nil`) stays text alone - no
    /// button, no chevron. A fix that puts the chevron on BOTH branches is the
    /// same byte-identical defect with an extra glyph. No shipping caller
    /// renders the footnote passively (RV.141 gave Home a destination), so
    /// `-homeExcludedFootnotePassive` (DEBUG-only) drives the branch a real
    /// caller would hit.
    func testPJ57PassiveCaptionRendersNoAffordance() {
        let app = launch(args: ["-seedHomeExcludedMix", "-homeExcludedFootnotePassive"])

        let caption = app.staticTexts["homeExcludedFootnote"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10),
                      "the passive caption must still render the count")
        XCTAssertFalse(app.buttons["homeExcludedFootnoteButton"].exists,
                       "a passive caption is not a door and must not read as a button")
        XCTAssertFalse(app.images["homeExcludedFootnoteChevron"].exists,
                       "a passive caption must not carry the chevron the link uses")
    }

    /// L4, EN at the largest text size: the link row (count phrase + chevron)
    /// fits inside the window. The chevron is the row's new widest element, and
    /// a glyph clipped at the trailing edge is the geometry this row exists to
    /// catch.
    func testPJ57LinkRowFitsAtXLInEnglish() {
        let app = launch(args: ["-seedHomeExcludedMix",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"])
        assertLinkRowFitsWindow(app)
    }

    /// L4, RU at the largest text size: Russian runs 20-30% longer, so the count
    /// phrase beside the chevron is the tightest the row ever gets - the case
    /// that breaks when the glyph is added.
    func testPJ57LinkRowFitsAtXLInRussian() {
        let app = launch(args: ["-seedHomeExcludedMix",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"],
                         language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        assertLinkRowFitsWindow(app)

        // Restore the app's persisted language (the same UserDefaults reset as
        // the RV.141 RU pass above).
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    /// The whole link row - the phrase AND the chevron - is inside the window's
    /// horizontal bounds after scrolling. Frame against the window, never
    /// isHittable alone (RV.84 measured isHittable true on an element 86%
    /// clipped).
    private func assertLinkRowFitsWindow(_ app: XCUIApplication) {
        let footnote = app.buttons["homeExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10),
                      "the link footnote must exist at the largest text size")
        scrollUntilHittable(footnote, in: app)

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(footnote.frame.minX, window.minX - 1,
                                    "the footnote row must not clip off the left")
        XCTAssertLessThanOrEqual(footnote.frame.maxX, window.maxX + 1,
                                 "the footnote row must not clip off the right")

        let chevron = app.images["homeExcludedFootnoteChevron"]
        XCTAssertTrue(chevron.exists,
                      "the link footnote must carry its chevron at the largest text size")
        XCTAssertGreaterThanOrEqual(chevron.frame.minX, window.minX - 1,
                                    "the chevron must not clip off the left")
        XCTAssertLessThanOrEqual(chevron.frame.maxX, window.maxX + 1,
                                 "the chevron must not clip off the right edge")
    }

    /// Footnote -> list, then: every row present, both reason phrases rendered,
    /// and each reason line fully inside the window's horizontal bounds (a
    /// clipped caption is the geometry the RV.141 RU pass exists to catch).
    private func assertExcludedListFitsWindow(_ app: XCUIApplication,
                                              listTitle: String,
                                              conflictPhrase: String,
                                              duplicatePhrase: String) {
        let footnote = app.buttons["homeExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10),
                      "the excluded footnote must exist at the largest text size")
        scrollUntilHittable(footnote, in: app)
        footnote.tap()

        XCTAssertTrue(app.navigationBars[listTitle].waitForExistence(timeout: 5),
                      "the footnote must reach the excluded-entries list at the largest text size")
        let rows = app.buttons.matching(identifier: "excludedEntryRow")
        XCTAssertEqual(rows.count, 2,
                       "both excluded rows must be present at the largest text size")

        let window = app.windows.firstMatch.frame
        let reasons = app.staticTexts.matching(identifier: "excludedEntryReason")
        XCTAssertEqual(reasons.count, 2)
        let labels = reasons.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains(conflictPhrase) },
                      "the conflict reason must render at XL, got \(labels)")
        XCTAssertTrue(labels.contains { $0.contains(duplicatePhrase) },
                      "the duplicate reason must render at XL, got \(labels)")
        for reason in reasons.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(reason.frame.minX, window.minX - 1,
                                        "a reason line must not clip off the left: \(reason.label)")
            XCTAssertLessThanOrEqual(reason.frame.maxX, window.maxX + 1,
                                     "a reason line must not clip off the right: \(reason.label)")
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        var attempts = 0
        while attempts < 12, !element.isHittable {
            scrollView.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable,
                      "the element never became reachable after \(attempts) swipes")
    }
}

// MARK: - Trends

@MainActor
extension TrendsUITests {

    /// Trends' regression guard: N == 1 keeps opening the flagged entry
    /// directly (the pre-RV.141 contract is pinned by the base suite's own
    /// test), and N > 1 now opens the same excluded-entries list Home opens -
    /// never a single entry that leaves the other N-1 unreachable.
    func testRV141TrendsFootnoteWithSeveralExcludedOpensTheList() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-selectTrendsTab", "-seedHomeExcludedMix",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let footnote = app.buttons["trendsExcludedFootnoteButton"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10))
        XCTAssertTrue(footnote.label.contains("2 entries excluded"),
                      "Trends must count what Home counts, got '\(footnote.label)'")
        scrollUntilHittable(footnote, app: app)
        footnote.tap()

        XCTAssertTrue(app.navigationBars["Excluded entries"].waitForExistence(timeout: 5),
                      "an N > 1 count must open the list from Trends too")
        XCTAssertEqual(app.buttons.matching(identifier: "excludedEntryRow").count, 2,
                       "the list must show every entry the count promised")
    }

    private func scrollUntilHittable(_ element: XCUIElement, app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        var attempts = 0
        while attempts < 12, !element.isHittable {
            scrollView.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable,
                      "the element never became reachable after \(attempts) swipes")
    }
}
