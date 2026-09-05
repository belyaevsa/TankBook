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

    private func launchSettingsRU(seed: String) -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                "-presentScreen", "settings", seed])
    }

    /// Launches Settings signed in and forces the account card's LIVE device
    /// count to `count` (`-seedSettingsDeviceCount`, RV.54), so the rendered
    /// plural forms can be asserted at 1/2/5 in either language without a real
    /// device fetch. The value semantics (live-only counting) are the L1
    /// contract; this pins the account card's rendering of it.
    private func launchSettingsDeviceCount(_ count: Int, language: String) -> XCUIApplication {
        launch(["-presentScreen", "settings", "-seedSettingsSynced",
                "-seedSettingsDeviceCount", "\(count)",
                "-AppleLanguages", "(\(language))", "-AppleLocale",
                language == "ru" ? "ru_RU" : "en_US"])
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
        let hint = app.staticTexts["settingsOfflineHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "an offline queue names its next step: back online")
        XCTAssertEqual(hint.label, "Will sync when you're back online",
                       "the offline row renders the passive sentence, never 'service unreachable'")
    }

    /// PR.13: a server 5xx is NOT the same sentence as offline. The server-down
    /// seed answers 503 for the sync, so the surface renders the "Sync service
    /// unreachable" card with Try again - never the passive "back online" row.
    /// The whole point of the split is the user-facing next step.
    func testServerDownShowsUnreachableCardNotOfflineHint() {
        let app = launchSettings(seed: "-seedSettingsServerDown")
        let card = app.otherElements["settingsServerCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "a 5xx shows the service-unreachable card")
        XCTAssertEqual(app.staticTexts["settingsServerCardMessage"].label,
                       "Sync service unreachable – your data is safe on this phone. "
                       + "It will go up automatically when the service is back.",
                       "the card names the service being down, not the offline sentence")
        XCTAssertTrue(app.buttons["settingsServerRetryButton"].exists,
                      "the server-down card names its next step: Try again")
        XCTAssertFalse(app.staticTexts["settingsOfflineHint"].exists,
                       "a 5xx is never the offline row 'Will sync when you're back online'")
    }

    /// PR.13 RU: the two sentences stay distinct in Russian. The server-down
    /// card renders its own RU sentence (never the passive offline one), and the
    /// offline row renders the passive RU sentence.
    func testServerDownAndOfflineRenderDistinctRussianSentences() {
        let serverDown = launchSettingsRU(seed: "-seedSettingsServerDown")
        XCTAssertTrue(serverDown.otherElements["settingsServerCard"].waitForExistence(timeout: 10))
        XCTAssertEqual(serverDown.staticTexts["settingsServerCardMessage"].label,
                       "Сервис синхронизации недоступен – ваши данные в безопасности на этом телефоне. "
                       + "Они отправятся автоматически, когда сервис снова заработает.",
                       "the RU server-down card names the service, never 'back online'")
        XCTAssertTrue(serverDown.buttons["settingsServerRetryButton"].exists)

        let offline = launchSettingsRU(seed: "-seedSettingsPending")
        XCTAssertTrue(offline.staticTexts["settingsOfflineHint"].waitForExistence(timeout: 10))
        XCTAssertEqual(offline.staticTexts["settingsOfflineHint"].label,
                       "Синхронизируется, когда вы снова будете в сети",
                       "the RU offline row renders the passive sentence, never 'service unreachable'")
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

    // MARK: - RV.58 the real 410 path is terminal (docs/TASKS.md RV.58)

    /// A REAL 410 (the seed transport answers 410 to every request, so the
    /// whole 410 -> cycle-stop -> session-drop path runs - nothing is forced)
    /// must end the account on this device: the signed-in account card and its
    /// sync surface are gone, the signed-out revoked card with its "sign in"
    /// next step appears, and the card's sign-in opens the flow. The vacuous
    /// trap the row names is asserting the card while the three minutes of
    /// traffic still happen behind it - here the session drop IS the traffic
    /// stop, asserted by the account surface no longer believing it is signed
    /// in (no account title, no "Sync now").
    func testReal410DropsTheSessionAndRoutesToSignIn() {
        let app = launchSettings(seed: "-seedSettingsRevoked410")
        // Drive the cycle deterministically, exactly as the auth-expired seed
        // does: the seed writes the session at Settings appear, then the tap
        // runs the real path against the 410-answering transport. The launch
        // foreground cycle can already have run that path (and dropped the
        // session) before Settings appears - if "Sync now" is still there, tap
        // it; either way the drop's card is what we assert.
        let syncNow = app.buttons["settingsSyncNowButton"]
        if syncNow.waitForExistence(timeout: 5) {
            syncNow.tap()
        }

        let revokedCard = app.otherElements["settingsRevokedCard"]
        XCTAssertTrue(revokedCard.waitForExistence(timeout: 10),
                      "a 410 must surface the revoked card, never 'update the app'")
        XCTAssertTrue(app.buttons["settingsRevokedSignInButton"].exists,
                      "the revoked card names its next step: sign in")

        // The session was dropped: the signed-in account card is gone, and so
        // is the sync surface it guarded. This is what ends the three-minute
        // tail - no session means no future trigger can start another cycle.
        XCTAssertFalse(app.staticTexts["settingsAccountTitle"].exists,
                       "the dropped session must not still render the signed-in account card")
        XCTAssertFalse(app.buttons["settingsSyncNowButton"].exists,
                       "a dropped session must not still offer 'Sync now'")

        // Sign-in is reachable: the card's button opens the flow.
        app.buttons["settingsRevokedSignInButton"].tap()
        XCTAssertTrue(app.buttons["signInAppleButton"].waitForExistence(timeout: 10),
                      "the revoked card's next step opens the sign-in flow")
    }

    /// Hard rules 1 and 8 after a 410: a revoked device keeps using the app
    /// locally. The signed-out revoked state (the session a 410 dropped, the
    /// mark persisted) still opens every screen and still owns its local log -
    /// the vehicle and its last odometer survive, exactly as after a sign-out.
    func testRevokedDeviceStillOpensItsScreensOffline() {
        let app = launch(["-presentScreen", "settings", "-seedSettingsRevokedSignedOut"])
        XCTAssertTrue(app.otherElements["settingsRevokedCard"].waitForExistence(timeout: 10),
                      "the signed-out revoked state renders the revoked card")
        XCTAssertFalse(app.buttons["settingsSyncNowButton"].exists,
                       "a revoked device has no sync surface - there is no session to sync with")

        // Pop back to Home: the local log opens and the last odometer survives
        // (119 000 only because the five seeded fills exist - a 410 that wiped
        // the log would show the vehicle's initial 118 000 and fail this).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 10),
                      "the vehicle survives a 410 (nothing local is deleted)")
        let odometer = app.staticTexts["homeOdometer"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        XCTAssertTrue(odometer.label.contains("119\u{00A0}000"),
                      "the last entry's odometer survives; got '\(odometer.label)'")
    }

    // MARK: - RV.70 no reachable entry point to the (v1-absent) paywall

    /// The Pro card is GONE from Settings, not merely disabled - a disabled
    /// control is still a reviewer-visible dead affordance, and a Pro entry
    /// point contradicts the listing's no-IAP declaration while the screen it
    /// pushed was blank (guideline 2.1). The card was the Settings root's only
    /// always-present `.paywall` door; asserting its absence is asserting that
    /// no control on the root reaches the blank pushed screen.
    func testSettingsHasNoProCardEntryPoint() {
        let app = launchSettings(seed: "-seedSettingsSynced")
        XCTAssertTrue(syncStatus(app).waitForExistence(timeout: 10),
                      "the synced Settings root rendered (the screen the Pro card used to sit on)")
        XCTAssertFalse(app.buttons["settingsProCard"].exists,
                       "the Pro card must be absent, never present-but-disabled")
        XCTAssertFalse(app.staticTexts["Tankbook Pro"].exists,
                       "no 'Tankbook Pro' affordance may remain anywhere on Settings")
    }

    /// The quota card (the second `.paywall` door, RV.70) renders ONLY under a
    /// forced `.quotaFull` - it is invisible by default, so a test that skipped
    /// the seed would pass against the bug. Forced, the card must render, name a
    /// real next step, and carry no control that leads to the blank paywall
    /// push (hard rule 7: Pro is cut from v1, so the next step is a wait and a
    /// reassurance, never a purchase).
    func testForcedQuotaCardNamesItsNextStepAndHasNoDeadControl() {
        let app = launchSettings(seed: "-seedSettingsQuota")
        let card = app.otherElements["settingsQuotaCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "the quota card must render when .quotaFull is forced")
        let nextStep = app.staticTexts["settingsQuotaNextStep"]
        XCTAssertTrue(nextStep.exists,
                      "the quota card names its next step in text")
        XCTAssertEqual(nextStep.label,
                       "Everything on this phone keeps working – new photos upload when space frees up.",
                       "the quota card's next step is the RV.70 copy, never an upsell")
        XCTAssertFalse(app.buttons["settingsQuotaProButton"].exists,
                       "the quota card's dead 'Tankbook Pro' control is gone, not disabled")
        XCTAssertFalse(app.staticTexts["Tankbook Pro"].exists,
                       "no 'Tankbook Pro' affordance may remain on the quota card")
    }

    /// The RV.70 copy in Russian: the quota card's next step is a full localised
    /// phrase (never a concatenation), and it must render without truncation on
    /// the forced state.
    func testForcedQuotaCardNamesItsNextStepInRussian() {
        let app = launchSettingsRU(seed: "-seedSettingsQuota")
        let card = app.otherElements["settingsQuotaCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "the quota card must render when .quotaFull is forced (RU)")
        let nextStep = app.staticTexts["settingsQuotaNextStep"]
        XCTAssertTrue(nextStep.exists,
                      "the quota card names its next step in text (RU)")
        XCTAssertEqual(nextStep.label,
                       "Всё на этом телефоне продолжает работать – новые фото загрузятся, когда освободится место.",
                       "the RU quota card's next step is the RV.70 copy")
        XCTAssertFalse(app.buttons["settingsQuotaProButton"].exists,
                       "the dead 'Tankbook Pro' control is gone in RU too")
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

    // MARK: - The "Export everything" row (PJ.36)

    /// The row that used to be a bare chevron now builds the WHOLE-ACCOUNT
    /// archive and hands it to the system share sheet (VISION.md's "one-tap
    /// CSV/JSON export – always free"). The pending seed's garage (one vehicle,
    /// five fills) is enough for a real archive; the share sheet appearing is
    /// the whole guarantee - the row must do something, never dead-end.
    func testExportRowOpensTheWholeAccountShareSheet() {
        let app = launchSettings(seed: "-seedSettingsPending")
        let row = app.buttons["settingsExportRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the Export everything row is reachable")
        if !row.isHittable {
            app.swipeUp()
        }
        row.tap()

        let shareCaption = app.otherElements["LP.CaptionBar.TopCaption"]
        XCTAssertTrue(shareCaption.waitForExistence(timeout: 20),
                      "the export row must open the system share sheet, not dead-end")
        XCTAssertTrue(shareCaption.label.contains("Tankbook"),
                      "the share sheet carries the whole-account export; got '\(shareCaption.label)'")
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

    // MARK: - Sign out (RV.40, docs/SYNC.md -> "Sign out")

    /// The mildest account exit is reachable from Settings, and after it the app
    /// is a guest with every local entry still present. The guest Home shows the
    /// garage card, not the log, so the surviving entries are asserted through a
    /// known entry's value: the last seeded fill's odometer (119 000) rides the
    /// garage card, and it is only 119 000 BECAUSE the five fills exist (the
    /// vehicle's initial odometer is 118 000). A sign-out that quietly wiped the
    /// log would show 118 000 and fail this - an "a screen changed" check would
    /// not.
    func testSignOutReachableFromSettingsAndTheLocalLogIsUntouched() {
        let app = launch(["-seedSettingsPending"])

        // The real path: Home -> gear -> Settings.
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let signOut = app.buttons["settingsSignOutButton"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        if !signOut.isHittable { app.swipeUp() }
        signOut.tap()

        let alert = app.alerts["Sign out?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["settingsSignOutConfirmButton"].firstMatch.tap()

        XCTAssertTrue(app.buttons["settingsSignInButton"].waitForExistence(timeout: 10),
                      "after sign-out the account card offers sign-in again (a guest)")

        // Back to Home; the seeded vehicle and its fills are still there.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Volvo V60"].waitForExistence(timeout: 5),
                      "the vehicle survives sign-out")
        let odometer = app.staticTexts["homeOdometer"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        XCTAssertTrue(odometer.label.contains("119\u{00A0}000"),
                      "the last entry's odometer survives (the log was not wiped); got '\(odometer.label)'")
    }

    /// A dirty queue must be named before anything happens (hard rule 7/8):
    /// the confirmation names the unsynced count, and cancelling drops nothing.
    func testSignOutWithDirtyQueueNamesTheUnsyncedChanges() {
        let app = launchSettings(seed: "-seedSettingsPending")

        let signOut = app.buttons["settingsSignOutButton"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        if !signOut.isHittable { app.swipeUp() }
        signOut.tap()

        let alert = app.alerts["Sign out?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(text.contains("5 unsynced changes"),
                      "the confirmation names the unsynced count; got '\(text)'")

        // Cancelling drops nothing: still signed in, sync surface present.
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["settingsSyncNowButton"].waitForExistence(timeout: 5),
                      "cancelling the confirmation leaves the session intact")
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

    // MARK: - RV.54 the account card's count is LIVE and pluralises (docs/JOURNEYS.md J11a)

    /// The card's "· N device(s)" suffix renders with the real plural forms in
    /// EN (device/devices) at 1, 2 and 5. RV.54 changed what the NUMBER means
    /// (live devices only, the L1 contract in `LiveDeviceCountTests`); this
    /// pins that whatever number the card is given still renders with the
    /// catalog's plural rules - a count that stopped pluralising would pass a
    /// value test and fail here.
    func testAccountCardDeviceCountPluralisesInEnglish() {
        let expected = [
            1: "Synced just now · 1 device",
            2: "Synced just now · 2 devices",
            5: "Synced just now · 5 devices"
        ]
        for (count, label) in expected.sorted(by: { $0.key < $1.key }) {
            let app = launchSettingsDeviceCount(count, language: "en")
            let status = syncStatus(app)
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, label,
                           "the card must render '\(label)' at a live count of \(count)")
        }
    }

    /// The RU plural is the risk RV.54 names: Russian has THREE plural forms
    /// (устройство / устройства / устройств at 1/2/5) and a revoked device is
    /// exactly what moves a count across them. A count that no longer
    /// pluralises, or pluralises by the total instead of the live count, fails
    /// here.
    func testAccountCardDeviceCountPluralisesInRussian() {
        let expected = [
            1: "Синхронизировано только что · 1 устройство",
            2: "Синхронизировано только что · 2 устройства",
            5: "Синхронизировано только что · 5 устройств"
        ]
        for (count, label) in expected.sorted(by: { $0.key < $1.key }) {
            let app = launchSettingsDeviceCount(count, language: "ru")
            let status = syncStatus(app)
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, label,
                           "the card must render '\(label)' at a live count of \(count)")
        }
    }
}
