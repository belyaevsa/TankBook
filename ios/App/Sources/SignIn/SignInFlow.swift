import Foundation
import Observation
import SwiftUI
import TankbookCore

/// The account's data as the Restoring screen presents it (JOURNEYS.md J11 ->
/// "the F7 verification stats before finishing"). Raw facts only; the view
/// composes the localised copy from them. Produced by `RestoreStatsProviding` -
/// nil means the account is empty (the wrong-provider signal).
struct RestoreSnapshot: Equatable, Sendable {
    var carCount: Int
    var carNames: [String]
    var entryCount: Int
    var earliestEntry: Date?
    var latestEntry: Date?
    var lastOdometerKm: Int?
    var lastOdometerDeviceName: String?
    var lastOdometerDaysAgo: Int?
    var email: String?
    var provider: AuthProvider
}

/// Supplies what the signed-in account holds. Injected because the real pull is
/// P4.5 (sync client); until then the production value reports an empty account
/// and the test/seed doubles supply the artboard state. Returns nil for an
/// empty account - which is exactly the wrong-provider signal.
protocol RestoreStatsProviding: Sendable {
    func snapshot(accountId: String) async throws -> RestoreSnapshot?
}

/// Monotonic photo-download progress for the Restoring screen. It lives on the
/// flow controller rather than in the view, so the screen being torn down and
/// re-presented (interruption) shows the same honest progress - never a reset,
/// never a number it did not earn (docs/JOURNEYS.md F7 -> "must not lie about
/// progress"; the resume itself is P4.7).
@MainActor
@Observable
final class RestoreProgress {
    private(set) var completed = 0
    private(set) var total = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var isActive: Bool { total > 0 && completed < total }

    /// Reports progress. Monotonic and clamped: `completed` never decreases and
    /// never exceeds `total`, so the bar can never claim work it has not done.
    func report(completed: Int, total: Int) {
        self.total = max(self.total, total)
        self.completed = min(max(self.completed, completed), self.total)
    }
}

/// The sign-in/restore state machine (docs/JOURNEYS.md J11a). Coordinates the
/// provider flow, the session exchange, the Keychain write and the J11a
/// decision, and owns the Restoring screen's progress so it survives
/// interruption. `@Observable` + `@MainActor` so the sheet re-renders on each
/// phase change.
@MainActor
@Observable
final class SignInFlow {
    enum Phase: Equatable {
        /// Provider selection (the Sign in sheet).
        case choosing
        /// A provider flow is in flight.
        case signingIn(AuthProvider)
        /// Empty account + restore intent (docs/JOURNEYS.md J11a).
        case wrongProvider(AuthProvider)
        /// The account has data - pull it.
        case restoring(RestoreSnapshot)
        /// A local log is uploading (the push itself is P4.5); transient.
        case uploading
    }

    private(set) var phase: Phase = .choosing
    /// A sign-in failure's next step (hard rule 7), already localised.
    private(set) var errorMessage: String?
    let restoreProgress = RestoreProgress()

    /// Whether the user came through "Already use Tankbook?".
    let arrivedViaRestore: Bool

    private let idTokenProvider: any IDTokenProvider
    private let authService: any AuthService
    private let sessionStore: any SessionStore
    private let restoreStats: any RestoreStatsProviding
    private let localHasData: () -> Bool

    /// Called when the sheet should close (dismissed by the user, or the flow
    /// finished without a screen to show - a plain sign-in or an upload).
    var onFinished: () -> Void = {}

    init(
        arrivedViaRestore: Bool,
        idTokenProvider: any IDTokenProvider,
        authService: any AuthService,
        sessionStore: any SessionStore,
        restoreStats: any RestoreStatsProviding,
        localHasData: @escaping () -> Bool
    ) {
        self.arrivedViaRestore = arrivedViaRestore
        self.idTokenProvider = idTokenProvider
        self.authService = authService
        self.sessionStore = sessionStore
        self.restoreStats = restoreStats
        self.localHasData = localHasData
    }

    /// Applies a launch-argument scenario (screenshots, UI tests): the wrong
    /// provider question, or a seeded restore. DEBUG/test-only.
    func applyScenarioIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        if arguments.contains("-signInWrongProvider") {
            phase = .wrongProvider(.apple)
        } else if arguments.contains("-signInRestore") {
            phase = .restoring(SignInTestSeed.restoreSnapshot())
        }
        #endif
    }

    /// The user tapped a provider. Runs the platform flow, exchanges the token
    /// and routes through the J11a decision.
    func startSignIn(provider: AuthProvider) {
        Task { await signIn(provider: provider) }
    }

    /// From the wrong-provider question: one tap switches to the other provider.
    func switchProvider(from current: AuthProvider) {
        signOutLocally()
        startSignIn(provider: current == .apple ? .google : .apple)
    }

    /// Sign out (the wrong-provider and Restoring escapes): the session goes,
    /// the local app is untouched (docs/SECURITY.md -> the sign-out test).
    func signOutLocally() {
        try? sessionStore.clear()
    }

    private func signIn(provider: AuthProvider) async {
        phase = .signingIn(provider)
        errorMessage = nil
        do {
            let identity = try await idTokenProvider.signIn(provider: provider)
            let session = try await authService.signIn(identity: identity)
            try sessionStore.save(session)

            let hasLocal = localHasData()
            let snapshot = try await restoreStats.snapshot(accountId: session.accountId)
            let outcome = SignInRouter.decide(SignInContext(
                arrivedViaRestore: arrivedViaRestore,
                accountHasData: snapshot != nil,
                localHasData: hasLocal))

            switch outcome {
            case .wrongProvider:
                phase = .wrongProvider(provider)
            case .restore:
                if let snapshot {
                    phase = .restoring(snapshot)
                } else {
                    onFinished()
                }
            case .uploadLocalLog:
                // J11a: the local log uploads, never overwrites. The push itself
                // is P4.5; nothing on the phone changes today (sync adds, never
                // migrates - docs/JOURNEYS.md J11a).
                onFinished()
            case .plainSignIn:
                onFinished()
            }
        } catch {
            errorMessage = L10n.localize("Couldn't sign in. Check your connection and try again, or keep using the app without an account.")
            phase = .choosing
        }
    }
}

/// A flow whose dependencies read the real Keychain and the real
/// (AuthenticationServices-backed) provider. The restore stats are a placeholder
/// until P4.5 lands the sync pull, so the production value reports an empty
/// account (nil) - which, for a restore intent, honestly lands on the
/// wrong-provider question rather than an invented answer.
extension SignInFlow {
    @MainActor
    static func makeDefault(arrivedViaRestore: Bool = false) -> SignInFlow {
        let sessionStore = KeychainSessionStore()

        #if DEBUG
        let scenario = SignInTestSeed.scenario()
        let restoreIntent = arrivedViaRestore || scenario != .none
        let idTokenProvider: any IDTokenProvider = scenario == .none
            ? AppIDTokenProvider()
            : SignInTestSeed.StubIDTokenProvider()
        let authService: any AuthService = scenario == .none
            ? makeRemoteAuthService(sessionStore: sessionStore)
            : SignInTestSeed.StubAuthService()
        let restoreStats: any RestoreStatsProviding = scenario == .none
            ? PendingSyncRestoreStats()
            : SignInTestSeed.stubRestoreStats()
        #else
        let restoreIntent = arrivedViaRestore
        let idTokenProvider: any IDTokenProvider = AppIDTokenProvider()
        let authService: any AuthService = makeRemoteAuthService(sessionStore: sessionStore)
        let restoreStats: any RestoreStatsProviding = PendingSyncRestoreStats()
        #endif

        return SignInFlow(
            arrivedViaRestore: restoreIntent,
            idTokenProvider: idTokenProvider,
            authService: authService,
            sessionStore: sessionStore,
            restoreStats: restoreStats,
            localHasData: { (try? AppStore.repository().hasLocalData()) ?? false }
        )
    }

    @MainActor
    private static func makeRemoteAuthService(sessionStore: any SessionStore) -> any AuthService {
        let bundled = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.app")!
        return RemoteAuthService(
            baseURL: bundled,
            transport: URLSessionTransport(),
            sessionStore: sessionStore,
            device: RemoteAuthService.SessionDevice(
                name: UIDevice.current.name,
                platform: "iOS"
            )
        )
    }
}

/// The production restore-stats value until P4.5: there is no sync pull yet, so
/// the account is reported as empty. Honest rather than invented - a restore
/// intent then reaches the wrong-provider question, and a fresh sign-in reaches
/// a plain dismissal.
struct PendingSyncRestoreStats: RestoreStatsProviding {
    func snapshot(accountId: String) async throws -> RestoreSnapshot? { nil }
}
