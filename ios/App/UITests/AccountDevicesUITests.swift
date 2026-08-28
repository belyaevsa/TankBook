import XCTest

/// P6.4 Account & devices screen UI tests (docs/SCREENMAP.md: Settings ->
/// account card, signed in -> AccountDevices). The server side shipped in
/// P4.9a/P4.9b; this is the surface for it.
///
/// The screen's two guarantees, pinned as BEHAVIOUR (the confirmation copy the
/// user actually reads on the destructive paths):
///
/// 1. **Revoke stops syncing, it erases nothing** - the confirm says "It stops
///    syncing with your account. Everything on it stays." (docs/API.md -> the
///    revoked device's next pull gets 410; its local data stays on it).
/// 2. **Delete account is a tombstone** - the log on this phone is never
///    touched (docs/SYNC.md, site/delete-account.md). The confirm says exactly
///    that, and the screen never implies local data is deleted - a user who
///    believes that will not trust the export that still works.
@MainActor
final class AccountDevicesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches straight into the Account & devices screen over the stub
    /// transport, with a signed-in session whose device id matches the
    /// fixture's "this device" row (account-devices-full.json).
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase",
            "-seedSettingsSynced",
            "-presentScreen", "accountDevices",
            "-accountStubDevices", "full",
            "-accountStubCurrentDevice",
        ] + arguments
        app.launch()
        return app
    }

    // MARK: - The device list renders from the server

    func testDeviceListRendersWithThisDeviceMarker() {
        let app = launch()
        let rows = app.otherElements.matching(identifier: "accountDeviceRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the list loads from the server")
        XCTAssertEqual(rows.count, 3, "all three seeded devices render")
        XCTAssertEqual(app.buttons.matching(identifier: "accountRevokeButton").count, 2,
                       "the two live devices are revocable")
        XCTAssertTrue(app.staticTexts["This device"].waitForExistence(timeout: 5),
                      "the session's own device is marked")
    }

    // MARK: - Revoke: stops syncing, erases nothing

    /// Revoking a device removes it from sync - the confirm says so honestly,
    /// and after confirming the row shows "Signed out".
    func testRevokeConfirmationSaysStopsSyncingAndDataStays() {
        let app = launch()
        let revoke = app.buttons["accountRevokeButton"].firstMatch
        XCTAssertTrue(revoke.waitForExistence(timeout: 10))
        revoke.tap()

        // The confirmation names the TRUE consequence (hard rule 7: the user
        // decides with the facts). This is the sentence the mutation guard
        // pins: if a future copy claims the device's data is erased, this fails.
        let alert = app.alerts["Revoke this device?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts[
            "It stops syncing with your account. Everything on it stays."].exists,
            "the revoke confirmation must say it stops syncing and that everything stays")

        alert.buttons["accountRevokeConfirmButton"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Signed out"].firstMatch.waitForExistence(timeout: 10),
                      "the revoked device's row reflects the server state after reload")
    }

    // MARK: - Delete account: a tombstone, local log untouched

    /// The delete confirmation states the tombstone truth: the account is
    /// deleted on the server, other devices stop syncing, and the log on THIS
    /// phone is not touched. Mutation 1 (claiming local data is removed) makes
    /// this fail.
    func testDeleteConfirmationSaysLocalLogIsNotTouched() {
        let app = launch()
        XCTAssertTrue(app.buttons["accountDeleteButton"].waitForExistence(timeout: 10))
        app.buttons["accountDeleteButton"].tap()

        // The full sentence is over the 128-char identifier cap, and a wrapped
        // alert message is exposed as one element PER LINE, so the assertions
        // join the visible lines and match against the whole message. Mutation
        // 1 (claiming local data is removed) flips the fragments below.
        let message = app.alerts["Delete account?"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        let alertText = message.staticTexts.allElementsBoundByIndex
            .map(\.label).joined(separator: " ")
        XCTAssertTrue(alertText.contains("The log on this phone is not touched"),
                      "the confirmation must say the phone log is not touched")
        XCTAssertTrue(alertText.contains("server copy is removed after 30 days"),
                      "the confirmation must say the SERVER copy is what is removed")

        // The footnote under the row repeats the guarantee on the screen itself.
        XCTAssertTrue(app.staticTexts[
            "Deleting the account doesn't touch the log on this phone."].exists)
    }

    /// Confirming delete signs this device out of the account (the server has
    /// told every device 410 on their next pull) and returns to Settings, which
    /// now offers sign-in - while the local log is untouched (the guest screen
    /// is not an empty garage).
    func testDeleteAccountReturnsToGuestSettings() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-homeResetDatabase", "-seedSettingsSynced",
            "-accountStubDevices", "full", "-accountStubCurrentDevice",
        ]
        app.launch()

        // Home -> Settings (the real path - no -presentScreen shortcut, so the
        // pop after deletion lands where the user actually came from).
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Settings -> Account & devices via the signed-in account card.
        let accountCard = app.buttons["settingsAccountCard"]
        XCTAssertTrue(accountCard.waitForExistence(timeout: 5))
        accountCard.tap()
        XCTAssertTrue(app.navigationBars["Account & devices"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["accountDeleteButton"].waitForExistence(timeout: 10))
        app.buttons["accountDeleteButton"].tap()

        let alert = app.alerts["Delete account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete account"].tap()

        // Back on Settings, signed out: the account card offers sign-in again.
        XCTAssertTrue(app.buttons["settingsSignInButton"].waitForExistence(timeout: 10),
                      "after account deletion this device is a guest on Settings")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    // MARK: - Failure states name their next step

    func testLoadFailureShowsRetryWithNextStep() {
        let app = launch(["-accountTransportOffline"])
        XCTAssertTrue(app.staticTexts[
            "Couldn't reach Tankbook – check your connection and try again."]
            .waitForExistence(timeout: 10),
            "a failed load names its next step, it never wallows")
        XCTAssertTrue(app.buttons["accountDevicesRetryButton"].waitForExistence(timeout: 5),
                      "the retry is on the card")
    }
}
