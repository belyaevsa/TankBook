import Foundation
import TankbookCore

/// P6.21: a seeded launch must never touch the network.
///
/// `SettingsTestSeed` plants a `"stub-access-token"` so signed-in states can be
/// screenshotted and UI-tested. Once P6.8b/P6.18b wired the launch and
/// foreground sync cycles, that seed started causing a REAL authenticated
/// request to the live API host on every seeded launch - with a token the
/// server can never accept.
///
/// The damage was not slowness. It made the app's rendered state depend on
/// production: with the API returning 502, every seeded Settings capture gained
/// a "Sync service unreachable" banner the seed never asked for, so
/// `P4.9b-settings-synced` showed "Synced just now" AND the unreachable banner
/// in one frame - a state no seed produces. Screenshots stopped being evidence
/// about the build and became evidence about the server.
///
/// Offline is also the FAST and DETERMINISTIC path: a reachable-but-slow or 5xx
/// server is the fragile case, not an unreachable one.
///
/// So under a seeded launch the transport fails immediately, with the same error
/// a genuinely offline device produces, and no socket is opened.
struct SeededLaunchTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

/// PR.1's UI-test seam: answers every request with a `401`, so a seeded
/// signed-in launch runs the real 401 -> refresh -> refresh-fails path and
/// surfaces the re-sign-in card (the expired-session state no real server can
/// produce deterministically in a screenshot). Stateless - the same 401 comes
/// back for the sync pull, the push and `/auth/refresh`.
struct AuthExpiredTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        TankbookHTTPResponse(status: 401)
    }
}

/// PJ.13's UI-test seam (`-signInSyncStub`): a transport that ANSWERS the sync
/// and account-devices endpoints, so the L4 "sign in pushes" test runs a real
/// sync cycle end-to-end under a seeded launch (which would otherwise be
/// offline, and a real server is out of the question). The pull is empty, the
/// push accepts every change, and `GET /account/devices` serves exactly this
/// device - the account the local log is being pushed into has one device.
struct SignInSyncStubTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let path = request.url.path
        if path.hasPrefix("/v1/sync/pull") {
            return Self.json([
                "records": [],
                "nextSince": 0,
                "more": false,
                "schemaPolicy": ["minSupported": 1, "current": 1]
            ])
        }
        if path.hasPrefix("/v1/sync/push"), let body = request.body {
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let changes = object?["changes"] as? [[String: Any]] ?? []
            var scn = 0
            let results: [[String: Any]] = changes.compactMap { change in
                guard let id = change["id"] else { return nil }
                scn += 1
                return ["id": id, "status": "accepted", "newScn": scn, "clamped": false]
            }
            return Self.json(["results": results])
        }
        if path.hasPrefix("/v1/account/devices") {
            let deviceID = (try? KeychainSessionStore().load())?.deviceId ?? UUID().uuidString
            return Self.json(["devices": [[
                "id": deviceID,
                "name": "This iPhone",
                "platform": "iOS",
                "lastSeenAt": "2026-08-29T10:00:00Z",
                "revoked": false
            ]]])
        }
        return TankbookHTTPResponse(status: 404)
    }

    private static func json(_ object: [String: Any]) -> TankbookHTTPResponse {
        let data = try? JSONSerialization.data(withJSONObject: object)
        return TankbookHTTPResponse(status: 200, body: data)
    }
}

enum SeededLaunch {
    /// True when the process was launched by a UI test or the screenshot script.
    ///
    /// Detected from the seed arguments themselves rather than from a dedicated
    /// flag, so every existing test and every line of `capture-screenshots.sh`
    /// is covered without editing them - and a NEW seed cannot forget to opt in.
    static func isSeeded(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains { argument in
            argument.hasPrefix("-seed")
                || argument == "-presentScreen"
                || argument == "-homeResetDatabase"
                || argument == "-forceLowPower"
        }
    }

    /// True only for the screenshot script, which passes `-freezeSyncState`.
    /// UI tests deliberately do NOT set it: they want the real opportunistic
    /// cycle, made deterministic by the offline transport above rather than by
    /// being switched off. Freezing it for them broke the very test that proves
    /// the Low Power resumer drains.
    static func freezesSyncState(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-freezeSyncState")
    }

    /// The transport to use for this launch: offline under a seed, real otherwise.
    /// The auth-expired seed is the one exception to "offline": it answers 401 so
    /// the real refresh path runs and fails (PR.1). PJ.13's sign-in stub answers
    /// success so the L4 sign-in flow can push for real.
    static func transport(_ arguments: [String] = ProcessInfo.processInfo.arguments)
        -> any TankbookHTTPTransport {
        if arguments.contains("-signInSyncStub") { return SignInSyncStubTransport() }
        if arguments.contains("-seedSettingsAuthExpired") { return AuthExpiredTransport() }
        if isSeeded(arguments) { return SeededLaunchTransport() }
        return URLSessionTransport()
    }
}
