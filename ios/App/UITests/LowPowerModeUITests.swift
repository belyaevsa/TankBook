import XCTest

/// P6.8 UI tests: the Settings status row gains the Low Power reason
/// (docs/SYNC.md -> Low Power Mode) and nothing else changes. The reason is
/// **reassurance, never a warning** - `inkSoft`, never amber, no badge, no
/// toast, no modal (hard rule 8) - it names what is deferred and that it
/// resumes automatically, and it vanishes the moment the mode ends.
///
/// The mode is forced with `-forceLowPower` (the DEBUG `AppPower` hook swaps
/// the injected `PowerStateProvider` for a mutable double) and the queue with
/// `-seedSettingsLowPower`. The load-bearing distinction is exercised here too:
/// the LAUNCH opportunistic cycle must pass `.background`, so with the mode on
/// it defers - no transport call, no offline hint, no server notice - which is
/// exactly what test 5 pins.
@MainActor
final class LowPowerModeUITests: XCTestCase {

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

    private func launchSettings(seed: String, _ extra: String...) -> XCUIApplication {
        launch(["-presentScreen", "settings", seed] + extra)
    }

    private func launchSettingsRU(seed: String, _ extra: String...) -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                "-presentScreen", "settings", seed] + extra)
    }

    private func syncStatus(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["settingsSyncStatus"]
    }

    private func lowPowerHint(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["settingsLowPowerHint"]
    }

    // MARK: - The reason renders on the waiting row (docs/SYNC.md, verbatim)

    func testLowPowerShowsReasonAndExplanationOnStatusRow() {
        let app = launchSettings(seed: "-seedSettingsLowPower", "-forceLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label,
                       "Waiting to sync · 5 changes · Low Power Mode is on",
                       "the S7 row gains the reason, not a severity")
        XCTAssertTrue(lowPowerHint(app).waitForExistence(timeout: 5),
                      "the explanation row names what is deferred and that it resumes automatically")
        XCTAssertFalse(app.staticTexts["settingsOfflineHint"].exists,
                       "a Low Power deferral is not an offline condition - no offline hint")
        XCTAssertFalse(app.staticTexts["settingsSyncNotice"].exists,
                       "a Low Power deferral is not a server condition - no notice")
    }

    func testLowPowerExplanationNamesDeferralAndResumeInEnglish() {
        let app = launchSettings(seed: "-seedSettingsLowPower", "-forceLowPower")
        let hint = lowPowerHint(app)
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        let label = hint.label
        XCTAssertTrue(label.contains("background sync"), "the copy names what is deferred: \(label)")
        XCTAssertTrue(label.contains("resume automatically"),
                      "the copy says it resumes automatically: \(label)")
        for forbidden in ["error", "failed", "problem", "can't", "pro", "$"] {
            XCTAssertFalse(label.lowercased().contains(forbidden),
                           "the reason must not read as an error or an upsell: '\(forbidden)' in '\(label)'")
        }
    }

    // MARK: - The control: the mode, not the queue, is what turns the reason on

    func testNoLowPowerReasonWhenTheModeIsOff() {
        // The same queue WITHOUT the forced mode is a plain S7 row - the reason
        // must be tied to the mode, never to the queue alone.
        let app = launchSettings(seed: "-seedSettingsLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Waiting to sync · 5 changes")
        XCTAssertFalse(lowPowerHint(app).exists,
                       "no Low Power explanation when the mode is off")
    }

    func testNoLowPowerReasonWhenNothingIsWaiting() {
        // The mode on with nothing pending defers nothing visible: no reason.
        let app = launchSettings(seed: "-seedSettingsSynced", "-forceLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Synced just now")
        XCTAssertFalse(lowPowerHint(app).exists,
                       "nothing waiting means no Low Power reason")
    }

    // MARK: - The reason is reassurance, never a warning (hard rule 8)

    func testLowPowerReasonIsNeverAnAttentionSurface() {
        let app = launchSettings(seed: "-seedSettingsLowPower", "-forceLowPower")
        XCTAssertTrue(syncStatus(app).waitForExistence(timeout: 10))
        XCTAssertTrue(lowPowerHint(app).exists)
        // No attention-styled notice, no offline hint, no alert, no sheet - the
        // mode is a normal state the OS put the device in, not an error.
        XCTAssertFalse(app.staticTexts["settingsSyncNoticeAttention"].exists)
        XCTAssertFalse(app.staticTexts["settingsOfflineHint"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    // MARK: - The launch cycle passes `.background` (deferral, not a run)

    func testLaunchCycleDefersUnderLowPower() {
        // The launch opportunistic cycle must pass `.background`: with the mode
        // on it defers - no transport call, no offline hint, no server notice.
        // A launch trigger that ignored Low Power would RUN the cycle, and its
        // network outcome (offline hint or a refused/server notice) would
        // surface here. The deferral is synchronous, so the assertion is
        // deterministic; a buggy launch trigger would need the network to come
        // back, which this wait window is long enough to catch.
        let app = launchSettings(seed: "-seedSettingsLowPower", "-forceLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label,
                       "Waiting to sync · 5 changes · Low Power Mode is on")
        XCTAssertTrue(lowPowerHint(app).exists)

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            XCTAssertFalse(app.staticTexts["settingsOfflineHint"].exists,
                           "a deferred cycle must never hit the transport")
            XCTAssertFalse(app.staticTexts["settingsSyncNoticeAttention"].exists,
                           "a deferred cycle must never produce a server notice")
            XCTAssertFalse(app.staticTexts["settingsSyncNotice"].exists)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    // MARK: - The user's own "Sync now" tap runs while the mode is on

    func testManualSyncNowRunsWhileTheModeIsOn() {
        // The load-bearing distinction (docs/SYNC.md -> Low Power Mode): Low
        // Power postpones OPPORTUNISTIC work, never a sync the user asked for.
        // The launch cycle under the mode defers (the reason row), but a tap on
        // "Sync now" must run - and its network outcome (an offline hint or a
        // server notice) must surface. If the manual path deferred like the
        // launch one, nothing network-related would ever appear and this test
        // would fail on the timeout.
        let app = launchSettings(seed: "-seedSettingsLowPower", "-forceLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label,
                       "Waiting to sync · 5 changes · Low Power Mode is on",
                       "the launch cycle deferred while the mode is on")

        let button = app.buttons["settingsSyncNowButton"]
        XCTAssertTrue(button.exists, "the manual trigger is present under Low Power")
        button.tap()

        // The tap runs: wait for the transport to answer (an offline hint, or
        // the server's response) - the proof the cycle was NOT deferred. A
        // silently cancelled tap has no next step (hard rule 7).
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if app.staticTexts["settingsOfflineHint"].exists
                || app.staticTexts["settingsSyncNotice"].exists
                || app.staticTexts["settingsSyncNoticeAttention"].exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("a user-initiated sync must run while the mode is on - no network outcome appeared")
    }

    // MARK: - The reason vanishes when the mode ends (L4)

    func testLowPowerReasonVanishesWhenTheModeEnds() {
        // `-endLowPowerAfter 3` flips the forced mode off and posts the
        // power-state-change notification, which the resumer and the surface
        // both observe: the deferred work drains and the reason row disappears.
        let app = launchSettings(seed: "-seedSettingsLowPower", "-forceLowPower", "-endLowPowerAfter", "3")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label,
                       "Waiting to sync · 5 changes · Low Power Mode is on",
                       "the reason is present while the mode is on")

        // Wait for the reason to vanish - the drain re-runs the sync (which in
        // a test simulator can land an offline hint), but the reason row itself
        // must be gone the moment the mode ends.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !status.label.contains("Low Power Mode is on")
                && !lowPowerHint(app).exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("the Low Power reason must vanish when the mode ends; still showing '\(status.label)'")
    }

    // MARK: - RU renders the same states (the localization-blind-spot guard)
    //
    // These two hardcode the RU chip copy on purpose - that is the point of
    // the guard - so they MUST be updated whenever that copy changes. RV.22
    // shortened it (the screenshot showed the old string truncating and
    // dropping the change count) and updated LocalizationGateP53Tests but not
    // this file, so both cases sat red from RV.22 until RV.59's agent found
    // them. Per-task suite selection is what hid it: nothing that ran
    // afterwards touched Low Power.

    func testLowPowerReasonRendersInRussian() {
        let app = launchSettingsRU(seed: "-seedSettingsLowPower", "-forceLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label,
                       "Ожидают отправки: 5 · энергосбережение")
        let hint = lowPowerHint(app)
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        let expectedRU = "Включён режим энергосбережения – фоновая синхронизация и загрузка фото "
            + "подождут и возобновятся автоматически."
        XCTAssertEqual(hint.label, expectedRU)
    }

    func testNoLowPowerReasonInRussianWhenTheModeIsOff() {
        let app = launchSettingsRU(seed: "-seedSettingsLowPower")
        let status = syncStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Ожидают отправки: 5")
        XCTAssertFalse(lowPowerHint(app).exists)
    }
}
