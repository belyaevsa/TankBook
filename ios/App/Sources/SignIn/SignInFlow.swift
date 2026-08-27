import Foundation
import Observation
import SwiftUI
import TankbookCore

/// The account's data as the Restoring screen presents it (JOURNEYS.md J11 ->
/// "the F7 verification stats before finishing"). Raw facts only; the view
/// composes the localised copy from them. Built from the core `RestoreStats`
/// plus the session identity.
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

extension RestoreSnapshot {
    /// Builds the view snapshot from the restore's verification stats. Device
    /// attribution ("from your Android phone") is a v2 field (docs/SCHEMA.md:
    /// author attribution is not a domain field) - nil here, the seed supplies
    /// it for the artboard state.
    init(stats: RestoreStats, email: String?, provider: AuthProvider, lastOdometerDeviceName: String? = nil) {
        self.carCount = stats.carCount
        self.carNames = stats.carNames
        self.entryCount = stats.entryCount
        self.earliestEntry = stats.earliestEntry
        self.latestEntry = stats.latestEntry
        self.lastOdometerKm = stats.lastOdometerKm
        self.lastOdometerDaysAgo = stats.lastOdometerDaysAgo
        self.lastOdometerDeviceName = lastOdometerDeviceName
        self.email = email
        self.provider = provider
    }
}

/// Runs the restore pull (pull from cursor 0 - docs/SYNC.md) and reduces its
/// outcome. Injected so the real sync pull (P4.7) and the test/seed doubles are
/// the same seam.
protocol RestoreProviding: Sendable {
    func restore(accountId: String) async -> RestoreOutcome
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

/// The sign-in/restore state machine (docs/JOURNEYS.md J11a, F7). Coordinates the
/// provider flow, the session exchange, the Keychain write, the restore pull and
/// the honest F7 states (restored / empty / unreachable). `@Observable` +
/// `@MainActor` so the sheet re-renders on each phase change.
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
        /// The account has data - the stats are shown before finishing.
        case restoring(RestoreSnapshot)
        /// The account is truly empty - the recovery entry point (docs/JOURNEYS.md
        /// F7: shown BEFORE the user can log anything, so a later-appearing backup
        /// never becomes a merge problem).
        case emptyRestore
        /// The backend is down - the honest F7 copy with its next steps.
        case restoreUnreachable
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
    private let restoreProvider: any RestoreProviding
    private let localHasData: () -> Bool

    /// The signed-in identity, kept so a retry can re-run the restore without
    /// re-authenticating.
    private var signedInAccountId: String?
    private var signedInEmail: String?
    private var signedInProvider: AuthProvider?

    /// Called when the sheet should close (dismissed by the user, or the flow
    /// finished without a screen to show - a plain sign-in or an upload).
    var onFinished: () -> Void = {}

    init(
        arrivedViaRestore: Bool,
        idTokenProvider: any IDTokenProvider,
        authService: any AuthService,
        sessionStore: any SessionStore,
        restoreProvider: any RestoreProviding,
        localHasData: @escaping () -> Bool
    ) {
        self.arrivedViaRestore = arrivedViaRestore
        self.idTokenProvider = idTokenProvider
        self.authService = authService
        self.sessionStore = sessionStore
        self.restoreProvider = restoreProvider
        self.localHasData = localHasData
    }

    /// Applies a launch-argument scenario (screenshots, UI tests): the wrong
    /// provider question, a seeded restore, an empty restore, or a down backend.
    /// DEBUG/test-only.
    func applyScenarioIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        // The specific flags before the general one: "-signInRestore" is a
        // prefix of "-signInRestoreEmpty"/"-signInRestoreUnreachable".
        if arguments.contains("-signInWrongProvider") {
            phase = .wrongProvider(.apple)
        } else if arguments.contains("-signInRestoreEmpty") {
            phase = .emptyRestore
        } else if arguments.contains("-signInRestoreUnreachable") {
            phase = .restoreUnreachable
        } else if arguments.contains("-signInRestore") {
            phase = .restoring(SignInTestSeed.restoreSnapshot())
        }
        #endif
    }

    /// The user tapped a provider. Runs the platform flow, exchanges the token
    /// and runs the restore.
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

    /// Retries the restore pull (the "Try again" next step on the unreachable
    /// state). Re-runs the same pull-from-zero; the cursor makes it resume.
    func retryRestore() {
        guard let accountId = signedInAccountId else { return }
        Task { await runRestore(accountId: accountId) }
    }

    /// The user accepts the empty account ("Start fresh") - the sheet closes to
    /// the ordinary empty garage.
    func acceptEmpty() {
        onFinished()
    }

    private func signIn(provider: AuthProvider) async {
        phase = .signingIn(provider)
        errorMessage = nil
        do {
            let identity = try await idTokenProvider.signIn(provider: provider)
            let session = try await authService.signIn(identity: identity)
            try sessionStore.save(session)
            signedInAccountId = session.accountId
            signedInEmail = session.email
            signedInProvider = provider

            // J11a: a local log uploads, never overwritten - it is never pulled
            // over (docs/JOURNEYS.md J11a).
            if localHasData() {
                onFinished()
                return
            }

            await runRestore(accountId: session.accountId)
        } catch {
            errorMessage = L10n.localize("Couldn't sign in. Check your connection and try again, or keep using the app without an account.")
            phase = .choosing
        }
    }

    /// Runs the restore (pull from 0) and routes through the honest F7 states.
    private func runRestore(accountId: String) async {
        let outcome = await restoreProvider.restore(accountId: accountId)
        switch outcome {
        case .restored(let stats):
            phase = .restoring(RestoreSnapshot(
                stats: stats, email: signedInEmail, provider: signedInProvider ?? .apple))
        case .empty:
            if arrivedViaRestore {
                phase = .wrongProvider(signedInProvider ?? .apple)
            } else {
                phase = .emptyRestore
            }
        case .unreachable:
            phase = .restoreUnreachable
        case .deviceRevoked:
            signOutLocally()
            errorMessage = L10n.deviceRevokedMessage
            phase = .choosing
        }
    }
}

/// A flow whose dependencies read the real Keychain and the real
/// (AuthenticationServices-backed) provider, and whose restore runs the real
/// sync pull from cursor 0 (P4.7).
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
        let restoreProvider: any RestoreProviding = scenario == .none
            ? makeRestoreProvider(sessionStore: sessionStore)
            : SignInTestSeed.stubRestoreProvider()
        #else
        let restoreIntent = arrivedViaRestore
        let idTokenProvider: any IDTokenProvider = AppIDTokenProvider()
        let authService: any AuthService = makeRemoteAuthService(sessionStore: sessionStore)
        let restoreProvider: any RestoreProviding = makeRestoreProvider(sessionStore: sessionStore)
        #endif

        return SignInFlow(
            arrivedViaRestore: restoreIntent,
            idTokenProvider: idTokenProvider,
            authService: authService,
            sessionStore: sessionStore,
            restoreProvider: restoreProvider,
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

    /// The real restore provider: `RestoreEngine` over a `SyncEngine` pulling
    /// from a fresh cursor (0 - restore and incremental catch-up are the same
    /// call, docs/API.md). The final cursor is persisted so the app's regular
    /// sync continues incrementally where the restore left off.
    @MainActor
    private static func makeRestoreProvider(sessionStore: any SessionStore) -> any RestoreProviding {
        guard let repository = try? AppStore.repository() else {
            return SignInTestSeed.StubRestoreProvider(outcome: .unreachable)
        }
        return SyncRestoreProvider(repository: repository, sessionStore: sessionStore)
    }
}

/// The production restore provider (P4.7): restore IS the sync engine pulling
/// from cursor 0. The blob gate is absent - a restore pull never uploads, and
/// photos are P4.6's lazy path (the inline thumbnail rides in the record
/// payload; the full rendition downloads on open).
private struct SyncRestoreProvider: RestoreProviding, @unchecked Sendable {
    let repository: TankbookRepository
    let sessionStore: any SessionStore

    func restore(accountId: String) async -> RestoreOutcome {
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.app")!
        let tokenProvider = KeychainTokenProvider(sessionStore: sessionStore)
        let transport = RemoteSyncTransport(
            baseURL: baseURL,
            transport: URLSessionTransport(),
            tokenProvider: tokenProvider
        )
        // A fresh cursor: restore always pulls from 0, never from a stale
        // account's cursor.
        let cursor = InMemorySyncCursorStore()
        let engine = SyncEngine(
            repository: repository,
            transport: transport,
            cursorStore: cursor,
            payloadMemory: InMemorySyncPayloadMemory()
        )
        let outcome = await RestoreEngine(engine: engine).restore()
        if case .restored = outcome, let finalCursor = try? cursor.load() {
            try? UserDefaultsSyncCursorStore().save(finalCursor)
        }
        return outcome
    }
}
