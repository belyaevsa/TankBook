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
        case flagged
        case revoked
        case quota
        case upgradeRequired
        case tierRefused
        case refused
        case rateLimited
    }

    static func state(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> State {
        if arguments.contains("-seedSettingsGuest") { return .guest }
        if arguments.contains("-seedSettingsSynced") { return .synced }
        if arguments.contains("-seedSettingsPending") { return .pending }
        if arguments.contains("-seedSettingsFlagged") { return .flagged }
        if arguments.contains("-seedSettingsRevoked") { return .revoked }
        if arguments.contains("-seedSettingsQuota") { return .quota }
        if arguments.contains("-seedSettingsUpgradeRequired") { return .upgradeRequired }
        if arguments.contains("-seedSettingsTierRefused") { return .tierRefused }
        if arguments.contains("-seedSettingsRefused") { return .refused }
        if arguments.contains("-seedSettingsRateLimited") { return .rateLimited }
        return .none
    }

    /// Whether the state renders with the five-fill dirty queue behind it: the
    /// pending state and every server-ahead state, because a refused or paced
    /// push leaves the queue exactly as S7 does (nothing is lost).
    fileprivate static func seedsQueue(_ state: State) -> Bool {
        switch state {
        case .pending, .upgradeRequired, .tierRefused, .refused, .rateLimited: return true
        default: return false
        }
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
        if state != .guest {
            try? store.save(stubSession())
        }

        // Transport-issue fixtures (410 revoked, blob-quota 429, offline with a
        // queue): real states the transport never produces in a screenshot.
        sync.forcedRevoked = (state == .revoked)
        sync.forcedQuotaPercent = (state == .quota) ? 95 : nil
        sync.forcedTransportUnavailable = (state == .pending)

        // P6.11 server-ahead fixtures (426 / 402 / unknown 4xx / 429): outcomes
        // this app version cannot provoke from a real server, forced so the
        // account card's notice is screenshot-able. Every one leaves a dirty
        // queue, exactly as a refused push does (S7).
        sync.forcedUpgradeRequired = (state == .upgradeRequired)
        sync.forcedRefused = refusedError(for: state)
        sync.forcedRetryAfterSeconds = (state == .rateLimited) ? 120 : nil

        if seedsQueue(state) || state == .flagged {
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
    /// artboard's account card ("driver@icloud.com").
    static func stubSession() -> AuthSession {
        AuthSession(
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            accountId: "settings-seed-account",
            deviceId: UUID().uuidString,
            provider: .apple,
            email: "driver@icloud.com"
        )
    }
}
