import Foundation
import TankbookCore

/// DEBUG/test seeding for the Settings screen (P4.9b) - the same launch-argument
/// hook pattern as `HomeTestSeed`. Each `-seedSettings*` argument produces one of
/// the six artboard states the UI tests and screenshots render. The signed-in vs
/// guest distinction is never invented: the seed writes a real session to the
/// Keychain (or clears it) and the screen reads it back through `SessionStore`.
enum SettingsTestSeed {

    enum State {
        case none
        case guest
        case synced
        case pending
        case flagged
        case revoked
        case quota
    }

    static func state(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> State {
        if arguments.contains("-seedSettingsGuest") { return .guest }
        if arguments.contains("-seedSettingsSynced") { return .synced }
        if arguments.contains("-seedSettingsPending") { return .pending }
        if arguments.contains("-seedSettingsFlagged") { return .flagged }
        if arguments.contains("-seedSettingsRevoked") { return .revoked }
        if arguments.contains("-seedSettingsQuota") { return .quota }
        return .none
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

        if state == .pending || state == .flagged {
            seed(repository: try? AppStore.repository(), state: state)
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

        if state == .pending {
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
