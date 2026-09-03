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
}
