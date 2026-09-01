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

    /// The in-flight restore (pull + photo download), so the Restoring screen's
    /// Cancel can stop it (PR.6 - a wait the user cannot escape is the bug this
    /// exists to remove).
    private var restoreTask: Task<Void, Never>?

    /// Whether the user came through "Already use Tankbook?".
    let arrivedViaRestore: Bool

    private let idTokenProvider: any IDTokenProvider
    private let authService: any AuthService
    private let sessionStore: any SessionStore
    private let restoreProvider: any RestoreProviding
    private let localHasData: () -> Bool
    /// The J11a first push (docs/JOURNEYS.md J11a -> First push): the one
    /// `.userInitiated` cycle that uploads the local log before the flow
    /// finishes - and the guarantee that the wrong-provider path never pushes.
    private let firstPush: SignInFirstPush

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
        localHasData: @escaping () -> Bool,
        firstPush: SignInFirstPush
    ) {
        self.arrivedViaRestore = arrivedViaRestore
        self.idTokenProvider = idTokenProvider
        self.authService = authService
        self.sessionStore = sessionStore
        self.restoreProvider = restoreProvider
        self.localHasData = localHasData
        self.firstPush = firstPush
    }

    /// Applies a launch-argument scenario (screenshots, UI tests): a seeded
    /// restore, an empty restore, or a down backend. DEBUG/test-only. The
    /// wrong-provider question is NOT a scenario here since PJ.3: it is
    /// reachable for real through the Welcome root's third path (an empty
    /// account arrived via restore), so the flag that faked it was retired.
    func applyScenarioIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        // The specific flags before the general one: "-signInRestore" is a
        // prefix of "-signInRestoreEmpty"/"-signInRestoreUnreachable".
        if arguments.contains("-signInRestoreEmpty") {
            phase = .emptyRestore
        } else if arguments.contains("-signInRestoreUnreachable") {
            phase = .restoreUnreachable
        } else if arguments.contains("-signInRestore") {
            phase = .restoring(SignInTestSeed.restoreSnapshot())
            // PR.6: put the photo-download progress on screen so the Cancel
            // affordance (and its screenshot) renders - the artboard's "38%".
            if arguments.contains("-seedRestoreProgress") {
                restoreProgress.report(completed: 38, total: 100)
            }
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

    /// Sign out (the wrong-provider and Restoring escapes): revokes the session
    /// server-side best-effort, then clears it locally (docs/SECURITY.md -> the
    /// sign-out test). The clear is synchronous - a following sign-in
    /// (`switchProvider`) must never race a stale clear - while the revoke
    /// (`DELETE /auth/session`) rides in the background with the captured
    /// bearer, so an offline sign-out still signs out locally (hard rule 1).
    func signOutLocally() {
        let session = try? sessionStore.load()
        if let session {
            Task { try? await authService.signOut(session) }
        }
        try? sessionStore.clear()
    }

    /// Retries the restore pull (the "Try again" next step on the unreachable
    /// state). Re-runs the same pull-from-zero; the cursor makes it resume.
    func retryRestore() {
        guard let accountId = signedInAccountId else { return }
        runRestore(accountId: accountId)
    }

    /// Abandons a restore in progress: cancels the in-flight pull, signs out
    /// locally and closes the sheet. The app's local data is untouched (hard
    /// rule 1). This is the Restoring screen's escape hatch - hard rule 7, the
    /// next step exists on the progress surface itself.
    func cancelRestore() {
        restoreTask?.cancel()
        restoreTask = nil
        signOutLocally()
        onFinished()
    }

    /// The user accepts the empty account ("Start fresh") - the account is
    /// accepted, so it receives the local log: one user-initiated cycle, then
    /// the sheet closes to the ordinary empty garage (docs/JOURNEYS.md J11a).
    func acceptEmpty() {
        Task { await finish(path: .acceptEmpty) }
    }

    /// Completes a sign-in path through the first-push coordinator. The
    /// upload/accept paths run exactly one `.userInitiated` cycle before the
    /// sheet closes; the wrong-provider path pushes nothing (its caller shows
    /// the question instead of finishing).
    private func finish(path: SignInFirstPush.Path) async {
        guard await firstPush.complete(path) else { return }
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
            // over (docs/JOURNEYS.md J11a). The upload is a user-initiated sync
            // that runs BEFORE the sheet closes.
            if localHasData() {
                await finish(path: .uploadLocalLog)
                return
            }

            runRestore(accountId: session.accountId)
        } catch GoogleOAuth.Failure.cancelled {
            // The user dismissed the browser sheet. Nothing failed, so nothing
            // is reported: an error that names a next step the user did not need
            // is still a false alarm (hard rule 7). This path is routine with a
            // web sheet in a way it never was with the Apple dialog.
            errorMessage = nil
            phase = .choosing
        } catch {
            errorMessage = L10n.localize("Couldn't sign in. Check your connection and try again, or keep using the app without an account.")
            phase = .choosing
        }
    }

    /// Runs the restore (pull from 0) and routes through the honest F7 states.
    /// Runs in a tracked task so the Restoring screen's Cancel can stop it.
    private func runRestore(accountId: String) {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            await self?.performRestore(accountId: accountId)
        }
    }

    private func performRestore(accountId: String) async {
        let outcome = await restoreProvider.restore(accountId: accountId)
        switch outcome {
        case .restored(let stats):
            phase = .restoring(RestoreSnapshot(
                stats: stats, email: signedInEmail, provider: signedInProvider ?? .apple))
        case .empty:
            // The wrong-provider question asks "did you sign in with Google?" -
            // which is only an honest question when this build offers Google
            // (SH.4). With one provider there is no other account to have used,
            // so the empty account is simply empty, and F7's recovery screen is
            // the truthful destination.
            if arrivedViaRestore && SignInView.offersGoogle {
                // The account is empty and the user expected their data: the
                // honest question - never the first push, because this account
                // has not been accepted. `complete(.wrongProvider)` pins that
                // it pushes nothing (PJ.13, L1).
                if await firstPush.complete(.wrongProvider) {
                    onFinished()
                } else {
                    phase = .wrongProvider(signedInProvider ?? .apple)
                }
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
    static func makeDefault(sync: AppSync, arrivedViaRestore: Bool = false) -> SignInFlow {
        let sessionStore = KeychainSessionStore()

        #if DEBUG
        let scenario = SignInTestSeed.scenario()
        // Every scenario except `.stubAuth` simulates the "Already use
        // Tankbook?" restore intent (the wrong-provider question needs it to
        // re-enter after a provider switch). `.stubAuth` is a real run - the
        // UI-test sign-in flow - so it keeps the caller's intent.
        let restoreIntent = arrivedViaRestore || (scenario != .none && scenario != .stubAuth)
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

        // The first push goes through the app's ONE coordinator (AppSync -
        // docs/SYNC.md: nothing else constructs a second SyncEngine), running
        // the user-initiated cycle the flow's completion paths must run. The
        // trigger choice lives in core (`SignInFirstPush`), asserted at L1.
        let firstPush = SignInFirstPush { _ in
            await sync.firstPushNow()
        }

        return SignInFlow(
            arrivedViaRestore: restoreIntent,
            idTokenProvider: idTokenProvider,
            authService: authService,
            sessionStore: sessionStore,
            restoreProvider: restoreProvider,
            localHasData: { (try? AppStore.repository().hasLocalData()) ?? false },
            firstPush: firstPush
        )
    }

    @MainActor
    private static func makeRemoteAuthService(sessionStore: any SessionStore) -> any AuthService {
        return RemoteAuthService(
            director: AppConfigStore.shared.director,
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
            return UnreachableRestoreProvider()
        }
        return SyncRestoreProvider(repository: repository, sessionStore: sessionStore)
    }
}

/// A restore that always reports the backend unreachable. This is the
/// degenerate fallback when the app's repository cannot be opened (no local
/// database), not a test double - a restore with no repository has nothing to
/// merge into, so "unreachable" is the honest outcome.
private struct UnreachableRestoreProvider: RestoreProviding, @unchecked Sendable {
    func restore(accountId: String) async -> RestoreOutcome { .unreachable }
}

/// The production restore provider (P4.7): restore IS the sync engine pulling
/// from cursor 0. The blob gate is absent - a restore pull never uploads, and
/// photos are P4.6's lazy path (the inline thumbnail rides in the record
/// payload; the full rendition downloads on open).
private struct SyncRestoreProvider: RestoreProviding, @unchecked Sendable {
    let repository: TankbookRepository
    let sessionStore: any SessionStore

    func restore(accountId: String) async -> RestoreOutcome {
        let tokenProvider = KeychainTokenProvider(sessionStore: sessionStore)
        let transport = RemoteSyncTransport(
            director: AppConfigStore.shared.director,
            transport: URLSessionTransport(),
            tokenProvider: tokenProvider,
            refresher: AppSessionRefresher.shared
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
