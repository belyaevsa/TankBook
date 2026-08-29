import XCTest

/// P4.9b Settings screen UI tests. The two guarantees this screen exists to
/// honour (docs/SYNC.md -> "The Settings sync surface"):
///
/// - Every account/sync state renders as the copy in docs/ERRORS.md -> Settings
///   (guest, synced, pending, flagged, revoked, quota), and the status row is
///   reassurance - never an amber warning with age.
/// - Domain conflicts surface as a **count and a link only**: the flagged row
///   navigates to the Log filtered to flagged entries, and Settings contains no
///   resolution control (hard rule 8 - a conflict is decidable only with the
///   entry in front of the user).
@MainActor
final class SettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func launchSettings(seed: String) -> XCUIApplication {
        launch(["-presentScreen", "settings", seed])
    }

    /// The status line's rendered text (the account card subtitle).
    private func syncStatus(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["settingsSyncStatus"]
    }

    // MARK: - Every state renders (docs/ERRORS.md -> Settings)

    func testGuestShowsSignInToSync() {
        let app = launchSettings(seed: "-seedSettingsGuest")
        XCTAssertTrue(app.buttons["settingsSignInButton"].waitForExistence(timeout: 10),
                      "the guest account card offers sign-in")
    }

    func testSyncedShowsReassuranceStatus() {
        let app = launchSettings(seed: "-seedSettingsSynced")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Synced just now")
        XCTAssertTrue(app.buttons["settingsSyncNowButton"].exists, "the manual trigger is present")
    }

    func testPendingShowsWaitingToSyncQueue() {
        let app = launchSettings(seed: "-seedSettingsPending")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Waiting to sync · 5 changes")
        XCTAssertTrue(app.staticTexts["settingsOfflineHint"].waitForExistence(timeout: 5),
                      "an offline queue names its next step: back online")
    }

    func testFlaggedShowsCountAndLinkOnly() {
        let app = launchSettings(seed: "-seedSettingsFlagged")
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("2 entries need a look"),
                      "the flagged count is derived and the row is a link")
    }

    func testRevokedShowsSignInCard() {
        let app = launchSettings(seed: "-seedSettingsRevoked")
        XCTAssertTrue(app.otherElements["settingsRevokedCard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settingsRevokedSignInButton"].exists,
                      "the revoked card names its next step: sign in")
    }

    func testQuotaShowsStorageCard() {
        let app = launchSettings(seed: "-seedSettingsQuota")
        XCTAssertTrue(app.otherElements["settingsQuotaCard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settingsQuotaProButton"].exists,
                      "the quota card names its next step: Pro")
    }

    /// PR.1: an expired session shows the re-sign-in card, never "update the
    /// app". The seed answers 401 for the sync AND the refresh, so the real
    /// 401 -> refresh -> refresh-fails path runs and the surface derives the
    /// card from the outcome (the card is asserted by nothing else).
    func testExpiredSessionShowsReSignInCardNotUpdateNotice() {
        let app = launchSettings(seed: "-seedSettingsAuthExpired")
        // The launch sync may already have expired the session; if it has not,
        // drive the cycle deterministically with "Sync now".
        let syncNow = app.buttons["settingsSyncNowButton"]
        if syncNow.waitForExistence(timeout: 5) {
            syncNow.tap()
        }
        XCTAssertTrue(app.otherElements["settingsAuthExpiredCard"].waitForExistence(timeout: 10),
                      "an expired session shows the re-sign-in card, not the update notice")
        XCTAssertTrue(app.buttons["settingsAuthExpiredSignInButton"].exists,
                      "the expired-session card names its next step: sign in")
        XCTAssertFalse(app.staticTexts["settingsSyncNoticeAttention"].exists,
                       "an expired session is never 'the server has moved ahead'")
    }

    // MARK: - The flagged row navigates to the filtered Log

    func testFlaggedRowNavigatesToFilteredLog() {
        let app = launchSettings(seed: "-seedSettingsFlagged")
        let row = app.buttons["settingsFlaggedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        XCTAssertTrue(app.navigationBars["Needs a look"].waitForExistence(timeout: 10),
                      "the flagged row navigates to the Log filtered to flagged entries")
        XCTAssertTrue(app.buttons["flaggedEntryRow"].waitForExistence(timeout: 5),
                      "the filtered Log lists the flagged entries")
    }

    // MARK: - Settings contains no resolution control (hard rule 8)

    func testSettingsHasNoResolutionControl() {
        let app = launchSettings(seed: "-seedSettingsFlagged")
        XCTAssertTrue(app.buttons["settingsFlaggedRow"].waitForExistence(timeout: 10))

        // A resolution control in Settings is a bug: a conflict is decidable
        // only with the entry in front of the user, so the only conflict
        // affordance is the count-and-link row.
        for label in ["Merge", "Keep both", "Resolve", "Fix"] {
            XCTAssertFalse(app.buttons[label].exists,
                           "Settings must not offer a \(label) control")
        }
        XCTAssertFalse(app.buttons["homeMergeButton"].exists)
        XCTAssertFalse(app.buttons["homeKeepBothButton"].exists)
    }

    // MARK: - PJ.13 the first push after sign-in (docs/JOURNEYS.md J11a)

    /// A seeded local log, sign in, and the account card reads the synced line
    /// and the confirmation WITHOUT leaving Settings. The flow runs a real
    /// push through the sign-in stub transport, and the card learns about it
    /// from the onDismiss refresh - a `.sheet` does not re-trigger the
    /// presenter's `.task` on iOS 26 (the P6.18b finding), so without that
    /// refresh the card stays on its pre-sign-in guest state and this test
    /// fails. That is the regression pin for mutation 3.
    func testSignInWithLocalLogShowsSyncedLineWithoutLeavingSettings() {
        // Each flag its own launch argument (a concatenated seed string would
        // arrive as ONE argument containing spaces and match nothing).
        let app = launch(["-presentScreen", "settings", "-seedSettingsLocalLog",
                          "-signInStubAuth", "-signInSyncStub"])

        // Guest card -> sign in.
        let signIn = app.buttons["settingsSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        signIn.tap()

        // The stub provider flow: one tap, no Apple ID UI.
        let apple = app.buttons["signInAppleButton"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

        // The flow uploads the local log (one user-initiated cycle) and closes;
        // the card, refreshed on dismissal, reads the signed-in state - the
        // device count and the J11a confirmation line.
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 15),
                      "after sign-in the card must read the synced line without leaving Settings")
        XCTAssertEqual(status.label, "Synced just now · 1 device",
                       "the reassurance line carries the device count (docs/JOURNEYS.md J11a)")
        XCTAssertTrue(app.staticTexts["settingsSignedInConfirmation"].waitForExistence(timeout: 5),
                      "the just-signed-in card shows 'Your garage now follows your account.'")
        XCTAssertFalse(app.buttons["settingsSignInButton"].exists,
                       "the guest card is gone once signed in")
    }
}
