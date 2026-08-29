import Foundation
import TankbookCore

/// DEBUG/test doubles and launch-argument scenarios for the sign-in flow, so
/// the Sign in, Restoring, empty-restore and server-down screens render (and the
/// wrong-provider flow runs) without a real Apple ID, a Google SDK, or a
/// reachable backend. The production path uses `AppIDTokenProvider` +
/// `RemoteAuthService` + the real sync restore; these are swapped in only under
/// the scenario arguments below.
enum SignInTestSeed {

    enum Scenario {
        case none
        /// PJ.13: stub provider + auth + restore so a UI test can run a REAL
        /// sign-in end-to-end (tap the provider, the flow runs, the first push
        /// fires) without an Apple ID, a Google SDK or a reachable backend.
        /// Unlike the other scenarios it forces no phase - the flow runs.
        case stubAuth
        /// The J11a wrong-provider question (docs/JOURNEYS.md J11a) is NOT a
        /// scenario since PJ.3: it is reachable for real - the Welcome root's
        /// third path over an empty stub account - so the flag that faked it
        /// was retired and the tests drive the real path.
        case restore
        case restoreEmpty
        case restoreUnreachable
    }

    static func scenario(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Scenario {
        if arguments.contains("-signInStubAuth") { return .stubAuth }
        // The specific flags before the general one: "-signInRestore" is a
        // prefix of "-signInRestoreEmpty"/"-signInRestoreUnreachable".
        if arguments.contains("-signInRestoreEmpty") { return .restoreEmpty }
        if arguments.contains("-signInRestoreUnreachable") { return .restoreUnreachable }
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

    /// Returns a fixed restore outcome, or the artboard restore under
    /// `-signInRestore`.
    struct StubRestoreProvider: RestoreProviding {
        let outcome: RestoreOutcome

        func restore(accountId: String) async -> RestoreOutcome { outcome }
    }

    static func stubAuthService() -> any AuthService { StubAuthService() }

    static func stubRestoreProvider() -> any RestoreProviding {
        let outcome: RestoreOutcome
        switch scenario() {
        case .restore:
            let snapshot = restoreSnapshot()
            outcome = .restored(RestoreStats(
                carCount: snapshot.carCount,
                carNames: snapshot.carNames,
                entryCount: snapshot.entryCount,
                earliestEntry: snapshot.earliestEntry,
                latestEntry: snapshot.latestEntry,
                lastOdometerKm: snapshot.lastOdometerKm,
                lastOdometerDaysAgo: snapshot.lastOdometerDaysAgo))
        case .restoreEmpty:
            outcome = .empty
        case .restoreUnreachable:
            outcome = .unreachable
        case .none, .stubAuth:
            outcome = .empty
        }
        return StubRestoreProvider(outcome: outcome)
    }
}
