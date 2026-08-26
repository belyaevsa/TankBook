import Foundation
import TankbookCore

/// DEBUG/test doubles and launch-argument scenarios for the sign-in flow, so
/// the Sign in and Restoring screens render (and the wrong-provider flow runs)
/// without a real Apple ID, a Google SDK, or a reachable backend. The production
/// path uses `AppIDTokenProvider` + `RemoteAuthService`; these are swapped in
/// only under the scenario arguments below.
enum SignInTestSeed {

    enum Scenario {
        case none
        case wrongProvider
        case restore
    }

    static func scenario(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Scenario {
        if arguments.contains("-signInWrongProvider") { return .wrongProvider }
        if arguments.contains("-signInRestore") { return .restore }
        return .none
    }

    // MARK: - The artboard's restore state

    /// The Restoring artboard's "Found in your account" data (2 cars, 428
    /// entries, last odometer 119 486 km from an Android phone yesterday).
    static func restoreSnapshot() -> RestoreSnapshot {
        var start = DateComponents()
        start.year = 2019
        start.month = 9
        start.day = 1
        var end = DateComponents()
        end.year = 2026
        end.month = 8
        end.day = 20
        return RestoreSnapshot(
            carCount: 2,
            carNames: ["Volvo V60", "ID.4"],
            entryCount: 428,
            earliestEntry: Calendar.current.date(from: start),
            latestEntry: Calendar.current.date(from: end),
            lastOdometerKm: 119_486,
            lastOdometerDeviceName: "Android phone",
            lastOdometerDaysAgo: 1,
            email: "driver@icloud.com",
            provider: .apple
        )
    }

    // MARK: - Doubles

    /// Returns a canned identity without presenting any system UI.
    struct StubIDTokenProvider: IDTokenProvider {
        func signIn(provider: AuthProvider) async throws -> ProviderIdentity {
            ProviderIdentity(provider: provider, idToken: "stub-id-token", email: "driver@icloud.com")
        }
    }

    /// Returns a canned session without touching the network.
    struct StubAuthService: AuthService {
        func signIn(identity: ProviderIdentity) async throws -> AuthSession {
            AuthSession(
                accessToken: "stub-access-token",
                refreshToken: "stub-refresh-token",
                accountId: UUID().uuidString,
                deviceId: UUID().uuidString,
                provider: identity.provider,
                email: identity.email
            )
        }

        func refresh(_ session: AuthSession) async throws -> AuthSession { session }

        func signOut(_ session: AuthSession) async throws {}
    }

    /// Returns a fixed snapshot, or nil (an empty account - the wrong-provider
    /// signal).
    struct StubRestoreStats: RestoreStatsProviding {
        let snapshot: RestoreSnapshot?

        func snapshot(accountId: String) async throws -> RestoreSnapshot? { snapshot }
    }

    static func stubAuthService() -> any AuthService { StubAuthService() }

    static func stubRestoreStats() -> any RestoreStatsProviding {
        StubRestoreStats(snapshot: scenario() == .restore ? restoreSnapshot() : nil)
    }
}
