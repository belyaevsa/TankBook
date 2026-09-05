import XCTest

/// RV.22 - the sync state chip beside the Settings gear (docs/SYNC.md -> "The
/// sync state chip"). The chip's mapping is L1-tested (`SyncChipTests`); this
/// suite asserts the PRESENTATION and the ROUTING the L1 layer cannot see:
///
/// - each state renders its own chip, named by its accessibility label - never
///   "a chip exists", which is true in every state and tests nothing;
/// - the chip is hittable;
/// - the tap destination differs by state: Sign in vs Settings vs the flagged
///   Log - three destinations, and that routing is half the feature;
/// - the in-flight state degrades under Reduce Motion (the RV.8 precedent).
///
/// Colour is deliberately never asserted: XCUITest cannot read hue, which is
/// exactly how P1.1 shipped an accent-red tab bar while its suite stayed green.
/// The hues are enforced by `PaletteAccentGuardTests` instead.
@MainActor
final class SyncChipUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-skipWelcome",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        return app
    }

    /// The chip on the ACTIVE (Log) root.
    private func chip(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["syncStateChip"]
    }

    // MARK: - Each state names itself (never "a chip exists")

    func testSignedOutChipNamesItsState() {
        let app = launch(["-seedSyncChipSignedOut"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Not signed in")
    }

    func testRevokedChipNamesItsState() {
        let app = launch(["-seedSyncChipRevoked"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Device signed out")
    }

    func testAuthExpiredChipNamesItsState() {
        let app = launch(["-seedSyncChipAuthExpired"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Sign in again")
    }

    func testQuotaChipNamesItsState() {
        let app = launch(["-seedSyncChipQuota"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Storage full")
    }

    func testSyncingChipNamesItsState() {
        let app = launch(["-seedSyncChipSyncing"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Syncing…")
    }

    func testWaitingChipNamesItsStateWithTheCount() {
        let app = launch(["-seedSyncChipWaiting"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Waiting to sync · 5 changes")
    }

    func testSyncedChipNamesItsState() {
        let app = launch(["-seedSyncChipSynced"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertEqual(chip(app).label, "Synced")
    }

    func testChipIsHittable() {
        let app = launch(["-seedSyncChipSynced"])
        XCTAssertTrue(chip(app).waitForExistence(timeout: 10))
        XCTAssertTrue(chip(app).isHittable)
    }

    // MARK: - The tap destination differs by state

    func testSignedOutChipTapsToSignIn() {
        let app = launch(["-seedSyncChipSignedOut"])
        let syncChip = chip(app)
        XCTAssertTrue(syncChip.waitForExistence(timeout: 10))
        syncChip.tap()
        XCTAssertTrue(app.buttons["signInAppleButton"].waitForExistence(timeout: 10),
                      "the signed-out chip taps to Sign in, never Settings")
        XCTAssertFalse(app.navigationBars["Settings"].exists,
                       "the signed-out chip must not navigate to Settings")
    }

    func testSyncedChipTapsToSettings() {
        let app = launch(["-seedSyncChipSynced"])
        let syncChip = chip(app)
        XCTAssertTrue(syncChip.waitForExistence(timeout: 10))
        syncChip.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10),
                      "the synced chip taps to Settings")
    }

    func testFlaggedDotTapsToFilteredLog() {
        let app = launch(["-seedSyncChipSynced", "-seedSyncChipFlagged"])
        let dot = app.buttons["syncFlaggedDot"]
        XCTAssertTrue(dot.waitForExistence(timeout: 10),
                      "a flagged queue rides a warn dot on the chip")
        XCTAssertEqual(dot.label, "2 entries need a look",
                       "the dot names the flagged count, not a bare hint")
        dot.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10),
                      "the dot taps to the Log filtered to flagged entries, never Settings")
    }

    // MARK: - Reduce Motion (the RV.8 precedent)

    func testSyncingChipStillRendersUnderReduceMotion() {
        let app = launch(["-seedSyncChipSyncing", "-forceReduceMotion"])
        let syncChip = chip(app)
        XCTAssertTrue(syncChip.waitForExistence(timeout: 10))
        XCTAssertEqual(syncChip.label, "Syncing…",
                       "under Reduce Motion the chip degrades to a still glyph, never a missing state")
    }

    // MARK: - RV.66 (2026-09-05): the account-wide conflict signal leads to the
    // account-wide list (docs/SYNC.md -> the sync state chip)

    /// The headline L4: TWO cars, the conflict on the NON-selected one. The
    /// selected car's Home is clean (no badge - Home's rows are the selected
    /// vehicle's), yet the account-wide warn dot is visible (a conflict exists
    /// somewhere). Tapping the CHIP BODY - the 44 pt natural target, not the
    /// 10 pt dot - must reach the conflicted entry WITHOUT the user switching
    /// cars first. That is the "user clicks and sees nothing" report: the body
    /// used to land on a Settings page with nothing highlighted, and the only
    /// route that worked was the tiny dot on the chip's corner.
    func testTwoCarConflictOnOtherCarChipBodyReachesTheEntry() {
        let app = launch(["-seedHomeRV66TwoCar", "-seedSettingsSignedIn"])

        // Car A (Volvo V60) is the default selection and its Home is clean -
        // the RV.66 premise: no conflict badge, nothing excluded.
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 10),
                      "car A must be the selected car")
        XCTAssertFalse(app.buttons["conflictBadgeButton"].exists,
                       "car-scoped Home must not show the other car's conflict")
        XCTAssertFalse(app.staticTexts["homeExcludedFootnote"].exists,
                       "a clean selected car has nothing excluded")

        // The account-wide signal is visible: the chip reads "Synced" (flagged
        // is not a sixth state) and the warn dot rides its corner. The dot can
        // appear while the launch cycle's post-sync refresh is still settling
        // the chip's state, so wait for the label rather than asserting it on
        // the dot's first frame.
        let syncChip = chip(app)
        XCTAssertTrue(syncChip.waitForExistence(timeout: 10))
        let synced = NSPredicate(format: "label == %@", "Synced")
        expectation(for: synced, evaluatedWith: syncChip)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["syncFlaggedDot"].waitForExistence(timeout: 10),
                      "the account-wide flagged count must ride the chip")

        // Following the CHIP BODY reaches the account-wide list, never a bare
        // Settings page and never a car switch.
        syncChip.tap()
        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10),
                      "the flagged chip body must tap to the filtered Log, not Settings")
        XCTAssertFalse(app.navigationBars["Settings"].exists,
                       "a flagged chip body landing on Settings is the RV.66 dead end")

        // The list is account-wide and names the car: the NON-selected car's
        // entry is reachable without switching first.
        let row = app.buttons.matching(identifier: "flaggedEntryRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "Rocket Fuel")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the account-wide list must show the other car's flagged entry")
        XCTAssertTrue(row.label.contains("Golf GTI"),
                      "the row must name the car the conflict is on; got '\(row.label)'")

        // Arriving at the ENTRY, not merely that a screen opened: the edit
        // screen shows the flagged entry's own station.
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 10))
        let station = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(station.waitForExistence(timeout: 5))
        XCTAssertTrue(station.label.contains("Rocket Fuel"),
                      "the edit screen must be the flagged entry, got '\(station.label)'")
    }

    /// L4: with the conflict on the SELECTED car, today's behaviour is
    /// unchanged. Home still surfaces the conflict as a badge where the data
    /// lives (hard rule 8) with the excluded footnote, and the badge still opens
    /// the entry - the fix only ever changed the chip body's route, never the
    /// Home log's contract. Switching to the flagged car is the user's informed
    /// act (the switcher is where "which car is this on" is answered), not a
    /// hunt the app forces.
    func testConflictOnSelectedCarHomeBadgeBehaviourUnchanged() {
        let app = launch(["-seedHomeRV66TwoCar", "-seedSettingsSignedIn"])

        // Switch to car B - the car whose entry is flagged - so the conflict is
        // now on the SELECTED car.
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 10))
        app.buttons["carSwitcherButton"].tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))
        let golf = app.buttons.matching(identifier: "carSwitcherRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "Golf GTI")).firstMatch
        XCTAssertTrue(golf.waitForExistence(timeout: 5))
        golf.tap()

        // The selected car's log shows its conflict exactly as before the fix.
        let badge = app.buttons["conflictBadgeButton"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10),
                      "the selected car's conflict badge must render (unchanged)")
        XCTAssertTrue(app.staticTexts["homeExcludedFootnote"].exists,
                       "the excluded footnote must still name the count (unchanged)")
        badge.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5),
                      "the conflict badge must still open the entry (unchanged)")
    }
}
