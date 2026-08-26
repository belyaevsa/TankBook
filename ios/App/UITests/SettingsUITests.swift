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
}
