#if DEBUG
import Foundation
import TankbookCore

/// DEBUG/test seeding for the Settings screen (P4.9b/P6.11) - the same
/// launch-argument hook pattern as `HomeTestSeed`. Each `-seedSettings*`
/// argument produces one of the artboard states the UI tests and screenshots
/// render. The signed-in vs guest distinction is never invented: the seed writes
/// a real session to the Keychain (or clears it) and the screen reads it back
/// through `SessionStore`.
enum SettingsTestSeed {
    enum State {
        case none
        case guest
        case synced
        case pending
        case serverDown
        case flagged
        case revoked
        case quota
        case upgradeRequired
        case tierRefused
        case refused
        case rateLimited
        case lowPower
        case authExpired
        /// RV.58: a signed-in seed over the `RevokedDeviceTransport` (which
        /// answers 410 to every request), so the L4 test drives the REAL
        /// revoked-device path: the sync cycle answers 410, drops the session
        /// and surfaces the signed-out revoked card. Deliberately NOT forced -
        /// no `forcedRevoked`, no invented outcome: the card is asserted to be
        /// produced by the drop, or the test fails.
        case revoked410
        /// RV.58: the POST-410 surface state - no session (a 410 dropped it,
        /// docs/SECURITY.md: a revoked device discards its tokens) and the
        /// persisted `deviceRevoked` mark, with a local log behind it. Renders
        /// the signed-out revoked card deterministically (no real cycle needs
        /// to run for a screenshot or the offline-usability L4 test) and proves
        /// hard rule 1/8 on the same screen a real 410 lands on.
        case revokedSignedOut
        /// PJ.13: a populated local log with NO session - the guest card offers
        /// sign-in and the sign-in flow uploads the log (docs/JOURNEYS.md J11a).
        case localLog
        /// PJ.13: the just-signed-in card - session, device count and the
        /// "Your garage now follows your account" confirmation, rendered by a
        /// frozen-sync screenshot (no real push or device fetch runs).
        case signedIn
    }

    static func state(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> State {
        // The argument-to-state map is data, not an if/else ladder - swiftlint
        // cyclomatic_complexity (HomeTestSeed's seedAction uses the same shape).
        let seeds: [String: State] = [
            "-seedSettingsGuest": .guest,
            "-seedSettingsSynced": .synced,
            "-seedSettingsPending": .pending,
            "-seedSettingsServerDown": .serverDown,
            "-seedSettingsFlagged": .flagged,
            "-seedSettingsRevoked": .revoked,
            "-seedSettingsQuota": .quota,
            "-seedSettingsUpgradeRequired": .upgradeRequired,
            "-seedSettingsTierRefused": .tierRefused,
            "-seedSettingsRefused": .refused,
            "-seedSettingsRateLimited": .rateLimited,
            "-seedSettingsLowPower": .lowPower,
            "-seedSettingsAuthExpired": .authExpired,
            "-seedSettingsRevoked410": .revoked410,
            "-seedSettingsRevokedSignedOut": .revokedSignedOut,
            "-seedSettingsLocalLog": .localLog,
            "-seedSettingsSignedIn": .signedIn
        ]
        for argument in arguments {
            if let state = seeds[argument] { return state }
        }
        return .none
    }

    /// Test/screenshot-only: the numeric value following a `-seed... <n>`
    /// argument, nil when absent or unparseable. Seed arguments are data (see
    /// `state` above); a number rides as a separate launch argument so a
    /// concatenated seed string cannot swallow it.
    private static func intValue(for argument: String, in arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
    }

    /// Whether the state renders with the five-fill dirty queue behind it: the
    /// pending state, the Low Power state (the queue the mode's postponement
    /// holds) and every server-ahead state, because a refused or paced push
    /// leaves the queue exactly as S7 does (nothing is lost).
    fileprivate static func seedsQueue(_ state: State) -> Bool {
        switch state {
        case .pending, .lowPower, .upgradeRequired, .tierRefused, .refused, .rateLimited,
             // RV.58: the signed-out revoked state still owns its local log -
             // the five fills give the offline-usability L4 test a value to
             // assert survives (the same 119 000 the sign-out test asserts).
             .revokedSignedOut: return true
        default: return false
        }
    }

    /// Writes the signed-in session at LAUNCH time - before any view appears -
    /// so the launch opportunistic sync (P6.8, `AppSync.runOpportunisticSync`)
    /// already sees a session and actually consults the Low Power policy at
    /// launch. The normal `seedIfRequested(sync:)` runs at Settings appear and
    /// re-writes the same session (idempotent) plus the forced fixtures and the
    /// queue. Call from the app root init, DEBUG/test only.
    static func seedSessionAtLaunchIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        // RV.17: the attachment viewer's slow-fetch seed (`-seedPhotoRemote`)
        // needs an account at launch so the viewer's on-demand fetch has a
        // fetcher the moment it opens (the `-openAttachmentViewer` screenshot
        // seam opens the viewer before Edit entry loads, so seeding the session
        // only there would race it). It has no `-seedSettings*` argument, so it
        // must run before the state guard below returns early for `.none`.
        PhotoSyncingTestSeed.seedSessionAtLaunchIfRequested()
        resetLanguageForTestsIfRequested(arguments)
        let state = Self.state(arguments)
        // The auth-expired seed is deliberately NOT planted at launch: the
        // launch opportunistic sync must see no session (a no-op), so the
        // re-sign-in card is produced deterministically by the "Sync now" tap
        // after `seedIfRequested` writes the session - never by racing the
        // launch sync's 401 -> refresh -> fail path against the seed.
        // The revoked-410 seed (RV.58) follows the same rule for the same
        // reason: the card must be produced by the "Sync now" tap running the
        // real 410 -> drop path, never by racing the launch cycle.
        // The local-log seed is guest: the L4 sign-in flow must START from the
        // guest card, so no session may exist at launch.
        guard state != .none, state != .guest, state != .authExpired,
              state != .localLog, state != .revoked410 else { return }
        let store = KeychainSessionStore()
        try? store.clear()
        if state == .revokedSignedOut {
            // RV.58: the post-410 surface - no session (a 410 dropped it), the
            // persisted revoked mark (so it renders even before Settings does,
            // and the chip reads it from the first frame).
            try? store.setDeviceRevoked(true)
        } else {
            try? store.save(stubSession())
        }
    }

    /// Test-only: `-languageReset` removes any stored AppleLanguages preference
    /// so a language UI test starts from "follow the system" (UserDefaults
    /// survive `-homeResetDatabase`, which wipes only the database). Called at
    /// launch, before any view reads the store.
    static func resetLanguageForTestsIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("-languageReset") else { return }
        UserDefaults.standard.removeObject(forKey: LanguagePreferenceStore.storedLanguageKey)
        UserDefaults.standard.removeObject(forKey: LanguagePreference.appleLanguagesKey)
    }

    /// Screenshot-only: `-languageSetPending <code>` writes a stored language
    /// choice WITHOUT opening the picker, so Settings renders the RV.42 pending
    /// notice on the Language row (a stored choice differing from the language
    /// actually running) with the picker closed - the state the notice must
    /// survive in. `simctl` cannot tap the picker's option and then dismiss it.
    /// Called at Settings appear, after `-languageReset` cleared any prior choice.
    static func setPendingLanguageForScreenshotIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-languageSetPending"),
              index + 1 < arguments.count else { return }
        let code = arguments[index + 1]
        UserDefaults.standard.set(code, forKey: LanguagePreferenceStore.storedLanguageKey)
        UserDefaults.standard.set([code], forKey: LanguagePreference.appleLanguagesKey)
    }

    @MainActor
    static func seedIfRequested(sync: AppSync) {
        let arguments = ProcessInfo.processInfo.arguments
        let state = Self.state(arguments)
        let resetting = arguments.contains("-homeResetDatabase")
        guard state != .none || resetting else { return }

        if resetting {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard state != .none else { return }

        // The Keychain outlives the database reset (`resetForTests` wipes the
        // SQLite file, not Keychain): clear it first so a prior run's sign-in
        // cannot leak into a "guest" shot, then write the seeded session.
        let store = KeychainSessionStore()
        try? store.clear()
        if state == .revokedSignedOut {
            // RV.58: no session - the 410 dropped it - only the persisted mark.
            try? store.setDeviceRevoked(true)
        } else if state != .guest, state != .localLog {
            try? store.save(stubSession())
        }

        // PJ.13 fixtures: the just-signed-in card renders a device count and
        // the confirmation even though the screenshot freezes the sync (no push
        // and no device fetch runs under `-freezeSyncState`).
        sync.forcedDeviceCount = (state == .signedIn) ? 1 : nil
        // RV.54: `-seedSettingsDeviceCount <n>` renders any LIVE device count
        // on a signed-in account card ("· N devices"), so the EN/RU plural
        // forms at 1/2/5 can be asserted (L4) and screenshotted without a real
        // device fetch. It rides as its own argument (never inside a
        // concatenated seed string - a launch argument containing spaces
        // matches nothing).
        if let count = Self.intValue(for: "-seedSettingsDeviceCount", in: arguments) {
            sync.forcedDeviceCount = count
        }
        sync.forcedJustSignedIn = (state == .signedIn)

        // Transport-issue fixtures (410 revoked, blob-quota 429, offline with a
        // queue, server 5xx): real states the transport never produces in a
        // frozen screenshot. `pending` is the offline-with-a-queue state
        // (PR.13's passive "back online" row); `serverDown` is the 5xx state
        // (the "service unreachable" card with Try again).
        sync.forcedRevoked = (state == .revoked)
        sync.forcedQuotaPercent = (state == .quota) ? 95 : nil
        sync.forcedOffline = (state == .pending)
        sync.forcedServerUnavailable = (state == .serverDown)

        // P6.11 server-ahead fixtures (426 / 402 / unknown 4xx / 429): outcomes
        // this app version cannot provoke from a real server, forced so the
        // account card's notice is screenshot-able. Every one leaves a dirty
        // queue, exactly as a refused push does (S7).
        sync.forcedUpgradeRequired = (state == .upgradeRequired)
        sync.forcedRefused = refusedError(for: state)
        sync.forcedRetryAfterSeconds = (state == .rateLimited) ? 120 : nil

        if seedsQueue(state) || state == .flagged || state == .localLog {
            seed(repository: try? AppStore.repository(), state: state)
        }
    }

    /// The four server-ahead states refuse the push with a dirty queue still
    /// waiting (docs/SYNC.md S7) - the row says what is waiting, not that
    /// something failed.
    private static func refusedError(for state: State) -> SyncServerError? {
        switch state {
        case .tierRefused: return .tierRefused
        case .refused: return .refused(status: 418)
        case .rateLimited: return .rateLimited(retryAfterSeconds: 120)
        default: return nil
        }
    }

    /// Seeds the derived-state data: a synced vehicle plus either five dirty
    /// fills (the "Waiting to sync · 5 changes" queue) or two flagged fills (the
    /// "2 entries need a look" count). The count is read back through
    /// `fetchDirtyRows` / `flaggedEntryCount`, never stored.
    private static func seed(repository: TankbookRepository?, state: State) {
        guard let repository else { return }
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle, syncState: .synced(scn: 1))

        if seedsQueue(state) {
            for daysAgo in 1...5 {
                let fill = HomeTestSeed.makeFill(
                    vehicleID: vehicle.id,
                    HomeTestSeed.FillSpec(daysAgo: daysAgo,
                                          odometer: 118_500 + daysAgo * 100,
                                          litres: 42.0, amount: "68.00",
                                          price: "1.62", stationID: nil))
                try? repository.upsertFillUp(fill, syncState: .dirty)
            }
        } else if state == .localLog {
            // PJ.13: the smallest populated local log - one live vehicle with a
            // dirty fill, so the sign-in flow's `localHasData()` flips to the
            // upload branch and the push has a row to send.
            let fill = HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 1, odometer: 118_500, litres: 42.3,
                                      amount: "71.02", price: "1.679", stationID: nil))
            try? repository.upsertFillUp(fill, syncState: .dirty)
        } else if state == .flagged {
            let flagged1 = HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 1, odometer: 118_500, litres: 42.3,
                                      amount: "71.02", price: "1.679", stationID: nil),
                conflict: .flagged(kind: .order, detectedAt: Date()))
            let flagged2 = HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 2, odometer: 118_000, litres: 41.0,
                                      amount: "68.50", price: "1.671", stationID: nil),
                conflict: .flagged(kind: .pace, detectedAt: Date()))
            try? repository.upsertFillUp(flagged1, syncState: .synced(scn: 2))
            try? repository.upsertFillUp(flagged2, syncState: .synced(scn: 3))
        }
    }

    /// The signed-in session the seeded states read back. The email matches the
    /// artboard's account card ("driver@icloud.com"). With
    /// `-accountStubCurrentDevice` the device id is the Account & devices
    /// fixture's "this device" row (account-devices-full.json), so the marker
    /// and the session agree; otherwise it is a fresh random id.
    static func stubSession() -> AuthSession {
        let arguments = ProcessInfo.processInfo.arguments
        let deviceID = arguments.contains("-accountStubCurrentDevice")
            ? "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
            : UUID().uuidString
        return AuthSession(
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            accountId: "settings-seed-account",
            deviceId: deviceID,
            provider: .apple,
            email: "driver@icloud.com"
        )
    }
}
#endif
