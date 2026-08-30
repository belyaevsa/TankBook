import XCTest

/// P1.4 Home screen tests. Home is mostly NOT the full state, so the substance
/// is the empty and partial states: guest, no car yet, car with zero entries
/// (the "no N/A tiles" assertion), one fill-up with no segment yet (the D4
/// hint), and the full state. The sync-shaped states (S2/S5/S7, reminder
/// banner) are presentation fixtures driven by launch arguments
/// (HomePresentables) because their real data arrives with P4; the guest
/// chrome is real data since PJ.3 - it renders whenever there is no session.
///
/// Every Home test resets the database first (`-homeResetDatabase`) so the five
/// states are isolated from each other and from the other suites' seeds.
///
/// PJ.3: the Home states under test are the SIGNED-IN layouts (the guest chrome
/// is a real state now, so a session is what renders the full/empty layouts;
/// a no-session launch shows the guest Home instead). Every launch is
/// deterministically signed in via `-seedSettingsSignedIn`; the guest test
/// clears it back (`-clearSessionAtLaunch`), and the Keychain survives
/// `-homeResetDatabase`, so without these the suite would be order-dependent
/// on whatever session a previous test left behind.
@MainActor
final class HomeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + args
        app.launch()
        return app
    }

    // MARK: - The five states

    /// The guest chrome is REAL since PJ.3: a car with no session is the guest
    /// Home (reached for real from the Welcome root's "Add your car" path) -
    /// no `-forceGuestHome` fixture remains. GuestHome.dc.html: the capture
    /// CTA, the import card and the privacy line are the guest's signature
    /// surfaces.
    func testGuestStateRendersGuestChrome() {
        let app = launch(args: ["-clearSessionAtLaunch", "-seedHomeEmptyVehicle"])

        XCTAssertTrue(app.staticTexts["Scan your first fill-up"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeGuestCaptureButton"].exists)
        XCTAssertTrue(app.buttons["homeGuestImportButton"].exists)
        XCTAssertTrue(app.staticTexts[
            "Everything stays on this phone. Sign in later only if you want a second device."].exists)
    }

    /// The no-car Home is the signed-in empty garage (the Welcome root only
    /// shows while there is no session, so a no-session no-car launch lands on
    /// Welcome - docs/SCREENMAP.md). A signed-in user with an empty garage gets
    /// the Add-car path, not an empty dashboard (docs/SCHEMA.md / J1).
    func testNoCarYetRoutesToAddCar() {
        // The helper signs the launch in, so this is the signed-in empty
        // garage: the Welcome root only shows while there is no session
        // (docs/SCREENMAP.md), and the Add-car path is the no-car Home's job.
        let app = launch(args: [])

        // The Add-car path, not an empty dashboard (docs/SCHEMA.md / J1).
        let addCar = app.buttons["homeAddFirstCarButton"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 10))
        addCar.tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
    }

    func testZeroEntryStateOmitsVitalsAndNoNATiles() {
        let app = launch(args: ["-seedHomeEmptyVehicle"])

        // The garage card is real (baseline odometer from the vehicle), but the
        // data-hungry vitals are OMITTED, not "N/A", "–", "-" or "0.0".
        XCTAssertTrue(app.staticTexts["homeOdometer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["homeHeadlineValue"].exists)
        XCTAssertFalse(app.staticTexts["homeMonthSpendTile"].exists)
        XCTAssertFalse(app.staticTexts["homeLastPriceTile"].exists)
        XCTAssertFalse(app.staticTexts["homeCostPerKmTile"].exists)

        // The literal no-N/A assertion: no rendered label is one of the
        // placeholder strings.
        let forbidden = ["N/A", "–", "-", "0.0"]
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !forbidden.contains($0) },
                      "placeholder tile rendered: \(labels)")
    }

    func testSingleFillShowsD4HintWithCaptureLink() {
        let app = launch(args: ["-seedHomeSingleFill"])

        // docs/ERRORS.md -> Home, row D4: the hint names the next step and the
        // capture link works (it opens the manual form - capture is P2.1).
        let hint = app.staticTexts["homeD4Hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["One more full tank and your consumption appears"].exists)
        XCTAssertFalse(app.staticTexts["homeHeadlineValue"].exists)

        app.buttons["homeD4CaptureButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    func testFullStateRendersVitalsRecentEntriesAndGroupedOdometer() {
        let app = launch(args: ["-seedHomeFullHistory"])

        // Headline and the two vitals tiles (HomeA artboard).
        let headline = app.staticTexts["homeHeadlineValue"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["homeMonthSpendTile"].exists)
        XCTAssertTrue(app.staticTexts["homeLastPriceTile"].exists)

        // Recent entries are reachable and route to Edit entry.
        XCTAssertTrue(app.buttons["logEntryButton"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["homeEntryAmount"].firstMatch.exists)

        // The odometer is the shared grouped formatter's output end to end
        // (HANDOVER.md open item 0): grouped with U+00A0, not "123600".
        //
        // It asserted U+2009 until 2026-08-25 and passed the whole of P1 while
        // the screen rendered NO separator at all - DIN Alternate Bold has no
        // glyph for the thin space, so it drew as nothing. Asserting the exact
        // separator here is right; the character had to change, and the glyph
        // check lives in `OdometerFormatTests.separatorHasAGlyphInTheDisplayFont`.
        let odometer = app.staticTexts["homeOdometer"].firstMatch
        XCTAssertTrue(odometer.exists)
        XCTAssertTrue(odometer.label.contains("123"), "odometer shows \(odometer.label)")
        XCTAssertTrue(odometer.label.contains("\u{00A0}"), "odometer not grouped: \(odometer.label)")
        XCTAssertFalse(odometer.label.contains("\u{2009}"),
                       "the thin space has no glyph in DIN and must never come back: \(odometer.label)")
    }

    func testConflictBadgeRoutesToEditEntry() {
        let app = launch(args: ["-seedHomeConflict"])

        // F9a/S3: the amber badge renders on the conflicting entry and routes
        // to Edit entry; the excluded count is footnoted.
        let badge = app.buttons["conflictBadgeButton"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["homeExcludedFootnote"].exists)
        XCTAssertTrue(app.staticTexts["1 entry excluded"].exists)

        badge.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
    }

    // MARK: - P1.5: the log stream

    /// The owned tab bar must not swallow the last row: after scrolling to
    /// the bottom of a long stream, the oldest entry is fully visible, above
    /// the bar, and tappable (P1.4's bottom-inset bug).
    func testLastRowClearsTheTabBar() {
        let app = launch(args: ["-seedHomeFullHistory"])

        let tabBar = app.descendants(matching: .any).matching(identifier: "tabbar").firstMatch
        let scrollView = app.scrollViews.firstMatch
        let lastEntry = app.buttons.matching(identifier: "logEntryButton")
            .allElementsBoundByIndex.last!
        XCTAssertTrue(lastEntry.waitForExistence(timeout: 10))

        // Scroll until the row is BOTH hittable and fully clear of the bar.
        // `isHittable` tests the element's centre, so it turns true while the
        // bottom edge is still tucked under the tab bar - stopping there made
        // this test pass alone and fail under suite load, purely on scroll
        // timing. The requirement is that the last row CAN be brought fully
        // into view, so scroll until it is, or run out of attempts.
        var attempts = 0
        while attempts < 10,
              !lastEntry.isHittable || lastEntry.frame.maxY > tabBar.frame.minY + 1 {
            scrollView.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(lastEntry.isHittable,
                      "last log entry never became reachable after \(attempts) swipes")
        XCTAssertTrue(lastEntry.frame.maxY <= tabBar.frame.minY + 1,
                      "last row (\(lastEntry.frame)) overlaps the tab bar (\(tabBar.frame))")

        lastEntry.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
    }

    /// Fuel kind is CONDITIONAL (docs/DESIGN.md): the seed car accepts petrol +
    /// diesel, so its petrol fills print "95"; a single-fuel petrol-only car
    /// printing "95" on every row would be noise and must not.
    func testFuelKindShownForMultiFuelAndHiddenForSingleFuel() {
        let multi = launch(args: ["-seedHomeFullHistory"])
        let kind = multi.staticTexts["logEntryFuelKind"].firstMatch
        XCTAssertTrue(kind.waitForExistence(timeout: 10))
        XCTAssertEqual(kind.label, "95")

        let single = launch(args: ["-seedHomeSingleFuelLog"])
        XCTAssertFalse(single.staticTexts["logEntryFuelKind"].exists,
                       "a single-fuel car must not print its usual fuel kind on every row")
    }

    /// The attachment is a glyph, not a word, and it only appears where a
    /// receipt or photo exists - carrying its accessibility label (colour and
    /// iconography are never the only channel).
    func testAttachmentGlyphAppearsOnlyOnEntriesThatHaveOne() {
        let app = launch(args: ["-seedHomeFullHistory"])

        // Two receipts in the seed: one shared by the purchase group (a single
        // glyph on the group header), one on the Ionity charge.
        let glyphs = app.images.matching(identifier: "logEntryAttachment")
        XCTAssertTrue(glyphs.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(glyphs.count, 2, "exactly the seeded receipts carry a glyph")
        for index in 0..<glyphs.count {
            XCTAssertEqual(glyphs.allElementsBoundByIndex[index].label, "Has attachment")
        }
    }

    /// A purchase group renders as ONE receipt: the header shows the grand
    /// total, the fuel member inside shows its own amount (hard rule 4), and
    /// collapsing folds the members back into one row.
    func testPurchaseGroupRendersAsOneReceiptAndCollapses() {
        let app = launch(args: ["-seedHomeFullHistory"])

        let toggle = app.buttons["logGroupToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))

        // The header carries the receipt grand total (fuel 71.02 + wash 8.00).
        let grandTotal = app.staticTexts["logGroupGrandTotal"]
        XCTAssertTrue(grandTotal.exists)
        XCTAssertTrue(grandTotal.label.contains("79.02"),
                      "group header must show the grand total, got \(grandTotal.label)")

        // Expanded by default: the two members are visible rows.
        XCTAssertEqual(app.buttons.matching(identifier: "logGroupMemberButton").count, 2)

        // Collapse: one row, members gone.
        toggle.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "logGroupMemberButton").count, 0)
    }

    // MARK: - Sync-shaped presentation states (fixtures until P4)

    func testSyncShapedPresentationStatesAreReachable() {
        let app = launch(args: ["-seedHomeEmptyVehicle",
                                "-forceArchivedReturned",
                                "-forceSyncToast"])

        // S5: archived car returned via sync, with its next steps.
        XCTAssertTrue(app.buttons["homeDeleteAgainButton"].exists)
        XCTAssertTrue(app.buttons["homeKeepButton"].exists)

        // S7: post-outage sync toast.
        XCTAssertTrue(app.staticTexts["Synced. 2 entries need a look"].waitForExistence(timeout: 5))
    }

    // MARK: - PJ.4 the reminder banner is real data (no fixture flag)

    /// The banner is REAL since PJ.4: a seeded due reminder renders it with the
    /// reminder's own title and the actual count, and View reaches the list -
    /// with NO `-forceReminderDue` and NO `-route` argument. The exact banner
    /// text is asserted, not just the banner's existence: a hardcoded fixture
    /// sentence would fail this (docs/ERRORS.md -> Home, row "Reminder due").
    func testReminderBannerDerivesFromRealReminderAndReachesList() {
        let app = launch(args: ["-seedHomeReminderDue"])

        let view = app.buttons["homeReminderViewButton"]
        XCTAssertTrue(view.waitForExistence(timeout: 10),
                      "a seeded due reminder must render the banner")

        // The banner names the ACTUAL reminder and its due count - never the
        // old "Insurance renews in 12 days" fixture sentence.
        XCTAssertTrue(textContaining(app, "Insurance renewal").exists,
                      "the banner must carry the real reminder's title")
        XCTAssertTrue(textContaining(app, "in 12 days").exists,
                      "the banner must carry the real due count")

        view.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Insurance renewal"].waitForExistence(timeout: 5),
                      "the banner reaches the list holding the same reminder")
    }

    // MARK: - P1.8: S2 duplicates (real data, docs/SYNC.md)

    /// One physical fill logged twice: the combined card renders where the two
    /// rows would otherwise appear, with BOTH next steps present and reachable
    /// (hard rule 7 - every warning names its resolution).
    func testDuplicateCardRendersWithBothActionsReachable() {
        let app = launch(args: ["-seedHomeDuplicate"])

        let card = anyElement(app, "homeDuplicateCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        // The title composes the station and the volume ("Shell, 42.3 L logged
        // twice") and both actions are reachable buttons.
        XCTAssertTrue(textContaining(app, "logged twice").exists)
        let merge = app.buttons["homeMergeButton"]
        let keepBoth = app.buttons["homeKeepBothButton"]
        XCTAssertTrue(merge.exists)
        XCTAssertTrue(merge.isHittable)
        XCTAssertTrue(keepBoth.exists)
        XCTAssertTrue(keepBoth.isHittable)
    }

    /// Keep both: the pair is resolved as two real purchases - the card goes
    /// away, both entries render as normal rows, and the excluded-count footnote
    /// drops to nothing (the number is derived, never hard-coded).
    func testKeepBothResolvesTheCardAndBothCount() {
        let app = launch(args: ["-seedHomeDuplicate"])

        XCTAssertTrue(anyElement(app, "homeDuplicateCard").waitForExistence(timeout: 10))
        XCTAssertTrue(textContaining(app, "logged twice").exists)
        let footnote = textContaining(app, "entry excluded")
        XCTAssertTrue(footnote.exists)

        app.buttons["homeKeepBothButton"].tap()

        // Resolved: the card is gone, the two entries are ordinary rows, and
        // nothing is excluded anymore.
        let resolved = NSPredicate(format: "NOT (exists == 1)")
        expectation(for: resolved, evaluatedWith: anyElement(app, "homeDuplicateCard"))
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons.matching(identifier: "logEntryButton").count, 2,
                       "Keep both must leave both fills as normal log rows")
        XCTAssertFalse(textContaining(app, "entry excluded").exists,
                       "a resolved pair excludes nothing")
    }

    /// Merge: the richer record survives, the other becomes a tombstone - the
    /// card goes away and only one live row remains (the tombstone's
    /// recoverability is asserted at L1 through the repository).
    func testMergeCollapsesThePairToOneLiveRow() {
        let app = launch(args: ["-seedHomeDuplicate"])

        XCTAssertTrue(anyElement(app, "homeDuplicateCard").waitForExistence(timeout: 10))
        app.buttons["homeMergeButton"].tap()

        let resolved = NSPredicate(format: "NOT (exists == 1)")
        expectation(for: resolved, evaluatedWith: anyElement(app, "homeDuplicateCard"))
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons.matching(identifier: "logEntryButton").count, 1,
                       "Merge must leave exactly one live fill row")
    }

    /// The excluded-count footnote is the REAL number, derived from the
    /// detector's flags: with one unresolved pair it reads "1 entry excluded".
    func testExcludedFootnoteShowsTheRealCountForADuplicate() {
        let app = launch(args: ["-seedHomeDuplicate"])

        XCTAssertTrue(anyElement(app, "homeDuplicateCard").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 entry excluded"].waitForExistence(timeout: 5),
                      "the footnote must report the one excluded pair member")
        XCTAssertTrue(textContaining(app, "entry excluded").exists)
    }

    // MARK: - P5.2b the F9 pending-rates footnote

    /// The footnote appears at N > 0: three foreign fills stored rate-pending
    /// render "3 entries pending rates" - the REAL derived count (P5.2a), never
    /// a hard-coded string.
    func testPendingRatesFootnoteAppearsAtNOverZero() {
        let app = launch(args: ["-seedHomePendingRates"])

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10),
                      "the F9 footnote must render while entries are rate-pending")
        XCTAssertTrue(footnote.label.contains("3 entries pending rates"),
                      "the footnote must show the derived count, got '\(footnote.label)'")
    }

    /// The footnote disappears at zero: an all-converted history renders no
    /// pending-rates line at all - nothing is wrong, so there is nothing to say.
    func testPendingRatesFootnoteIsGoneAtZero() {
        let app = launch(args: ["-seedHomeFullHistory"])

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["homePendingRatesFootnote"].exists,
                       "at zero the footnote must disappear, not render '0 entries'")
    }

    /// The pending -> filled transition (docs/SYNC.md S8) is SILENT and now
    /// driven by the real product path (PJ.8): the launch rate refresh fetches
    /// a stub pack and the S8 backfill fills the pending rows - with NO
    /// `-runRateBackfill` hook - and no toast, alert or banner may appear.
    func testPendingToFilledTransitionShowsNoToastBannerOrAlert() {
        // Phase 1: pending renders - no stub, and the pending fill-ups are dated
        // outside the bundled seed pack, so nothing can fill them. Signed in
        // like the rest of the suite, so the log stream (not the guest Home)
        // is the layout under test.
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", "-seedHomePendingRates"]
        app.launch()

        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "homeEntryAmount").count, 3,
                       "before backfill only the three EUR rows show amounts")
        XCTAssertFalse(app.buttons["deltaToast"].exists)
        XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                      "pending is not an error: no alert")

        // Phase 2: relaunch with the stub rate transport. The launch refresh
        // fetches the stub pack and the S8 backfill fills the three pending
        // rows - silently, through the product trigger, not the debug hook.
        app.terminate()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomePendingRates", "-stubRates"]
        app.launch()

        // The pending state may or may not render before the instant stub
        // backfill lands; either way the footnote must be GONE once filled.
        let after = app.staticTexts["homePendingRatesFootnote"]
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: after)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(app.staticTexts.matching(identifier: "homeEntryAmount").count, 6,
                       "after backfill all six rows show their home amount")
        XCTAssertFalse(app.buttons["deltaToast"].exists,
                       "a backfill must never show a toast (S8)")
        XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                      "a backfill must never show an alert (S8)")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].exists,
                      "nothing covered Home - no banner, no modal (S8)")
    }

    // MARK: - Helpers

    private func textContaining(_ app: XCUIApplication, _ substring: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
