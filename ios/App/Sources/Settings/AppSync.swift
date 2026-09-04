import Foundation
import Observation
import TankbookCore
import UIKit

/// Builds the app's one `SyncCoordinator` over the real repository, transport
/// and session store (docs/SYNC.md: one sync path - the trigger and the
/// transport live here, nothing else constructs a second `SyncEngine`).
@MainActor
enum SyncService {
    static func makeCoordinator(repository: TankbookRepository,
                                sessionStore: any SessionStore,
                                powerState: any PowerStateProvider) -> SyncCoordinator {
        let director = AppConfigStore.shared.director
        let tokenProvider = KeychainTokenProvider(sessionStore: sessionStore)
        let refresher = AppSessionRefresher.shared
        let transport = RemoteSyncTransport(
            director: director,
            transport: makeAppTransport(),
            tokenProvider: tokenProvider,
            refresher: refresher
        )
        // P4.6: the blob gate hooks attachments into the push loop - a live
        // attachment record uploads its rendition (begin -> PUT -> commit)
        // before it pushes, and defers otherwise (docs/SYNC.md, upload step 5).
        let blobGate = LocalFileBlobPushGate(
            uploader: BlobUploader(transport: RemoteBlobTransport(
                director: director, transport: makeAppTransport(), tokenProvider: tokenProvider,
                refresher: refresher)),
            source: FileBackedBlobSource(directory: (try? VehiclePhotoStore.attachmentsDirectory()) ?? FileManager.default.temporaryDirectory)
        )
        let engine = SyncEngine(
            repository: repository,
            transport: transport,
            cursorStore: UserDefaultsSyncCursorStore(),
            // PR.4: the payload memory is persisted, not in-memory - the
            // field-level Vehicle merge must survive a relaunch, or the first
            // sync after it claims every field changed and a stale device can
            // revert another device's edit (docs/SYNC.md S9, hard rule 13).
            payloadMemory: DatabaseSyncPayloadMemory(repository: repository),
            blobGate: blobGate,
            powerState: powerState
        )
        return SyncCoordinator(engine: engine, powerState: powerState)
    }

    /// The lazy-download fetcher for opening an entry (docs/SYNC.md -> Delivery):
    /// nil when signed out - a guest never downloads, and the inline thumbnail
    /// still renders the chip. The fetch verifies the sha256 and caches forever
    /// after; a failure leaves the "photo syncing" shimmer, never an error.
    static func makeBlobFetcher(sessionStore: any SessionStore) -> LazyBlobFetcher? {
        guard (try? sessionStore.load()) != nil else { return nil }
        #if DEBUG
        // RV.17: a seeded slow transport wins so the viewer's progress state is
        // observable from a UI test; it never ships (the transport seam is
        // DEBUG-only, exactly like the sync stubs in SeededLaunchTransport).
        if let seeded = SeededBlobTransport.from() {
            let store = FileBackedBlobStore(
                directory: (try? VehiclePhotoStore.attachmentsDirectory())
                    ?? FileManager.default.temporaryDirectory)
            return LazyBlobFetcher(transport: seeded, store: store)
        }
        #endif
        let transport = RemoteBlobTransport(
            director: AppConfigStore.shared.director,
            transport: makeAppTransport(),
            tokenProvider: KeychainTokenProvider(sessionStore: sessionStore),
            refresher: AppSessionRefresher.shared
        )
        let store = FileBackedBlobStore(
            directory: (try? VehiclePhotoStore.attachmentsDirectory())
                ?? FileManager.default.temporaryDirectory)
        return LazyBlobFetcher(transport: transport, store: store)
    }
}

/// Supplies the current access token to the sync transport, read from the
/// Keychain exactly as the auth service does (docs/SECURITY.md -> the token is
/// bound to the host, not the session). The host allowlist is enforced by
/// `TankbookHTTPClient` before this is consulted. Internal (not private) so the
/// sign-in restore provider (P4.7) reuses the same token path.
struct KeychainTokenProvider: AuthorizationTokenProvider {
    let sessionStore: any SessionStore

    func token() -> String? {
        try? sessionStore.load()?.accessToken
    }
}

/// The app's single sync surface (docs/SYNC.md -> "The Settings sync surface").
/// Owns the one `SyncCoordinator` and derives the Settings status from it plus
/// the repository's recomputed counts. Signed-in vs guest is read from the
/// session store, never invented (the Keychain is the source of truth).
///
/// `@Observable` + `@MainActor` so the Settings view re-renders when the state
/// changes; the heavy idempotency gate lives in the core `SyncCoordinator`.
@MainActor
@Observable
final class AppSync {
    let sessionStore: any SessionStore
    /// The config service the sync gate reads (P6.18b): under `.required` a
    /// push is withheld client-side - the server has stopped supporting this
    /// build, the same set 426 already withholds (docs/CONFIG.md). Everything
    /// local is untouched; a paused push leaves the queue exactly as S7 does.
    private let configService: AppConfigService
    private var core: SyncCoordinator?

    /// The injected Low Power Mode state (P6.8, docs/SYNC.md -> Low Power
    /// Mode). Never `ProcessInfo` read at a call site - the app's one seam is
    /// `AppPower`, and the deferral decision is the injected boolean's alone.
    private let powerState: any PowerStateProvider
    /// Drains the work a background cycle deferred, the moment the mode ends -
    /// resume on the state change, not at next launch. The same resumer the
    /// rate refresh registers its deferred fetch on.
    private let resumer: LowPowerResumer
    private var powerChangeObserver: NSObjectProtocol?
    /// One stable id for the deferred-sync work, so a second deferral replaces
    /// the first registration instead of stacking a duplicate drain.
    private static let deferredSyncID = UUID()

    private(set) var session: AuthSession?
    private(set) var dirtyCount = 0
    private(set) var flaggedCount = 0
    private(set) var lastSyncDate: Date?
    private(set) var lastOutcome: SyncOutcome?
    private(set) var isSyncing = false
    /// RV.26: whether the session store carries the persisted `authExpired` mark
    /// (a rejected refresh). Read in `refresh` and OR-ed into the surface state,
    /// so an expiry the cloud gateway detected - not only one a sync cycle
    /// detected - surfaces as "session expired - sign in again" in Settings and
    /// on RV.22's chip. Distinct from `lastOutcome.authExpired`, which is the
    /// in-memory outcome of the last sync cycle.
    private(set) var storedAuthExpired = false
    /// PR.14: the number of entries the last sync batch flagged (docs/SYNC.md
    /// -> the post-batch toast "Synced. N entries need a look"). Nil while no
    /// batch has flagged anything; the Home toast reads it and clears it when
    /// the user taps through. Derived from the outcome, never a stored counter.
    private(set) var lastBatchFlaggedEntries: Int?

    /// PJ.13 (docs/JOURNEYS.md J11a -> First push): whether the user just
    /// signed in and the first push ran, so the account card shows the one-line
    /// "Your garage now follows your account" confirmation. Set by the sign-in
    /// flow's first push, cleared on sign-out or relaunch; in-memory only.
    private var didJustSignIn = false
    /// The account's device count from `GET /account/devices` (docs/JOURNEYS.md
    /// J11a -> First push: "Synced just now · 1 device"). Refreshed on every
    /// surface refresh; nil while unknown (guest, offline, a fetch failure) -
    /// the card then shows the ordinary status line without the count.
    private var fetchedDeviceCount: Int?
    /// RV.18: when the last opportunistic (launch/foreground) cycle started, so
    /// a burst of `.active` transitions is one cycle, not one each. Only the
    /// launch/foreground door reads it - the Settings "Sync now" tap, the retry
    /// backoff and the Low Power drain never consult it, so a forced cycle is
    /// always available.
    private var lastOpportunisticSyncAt: Date?

    /// DEBUG/test fixtures for states a real transport never produces in a
    /// screenshot (410 device revoked, blob-quota 429, offline with a queue).
    /// Nil/absent = not forced; production never sets them.
    var forcedRevoked = false
    var forcedQuotaPercent: Int?
    /// PJ.13 fixtures for the just-signed-in card (the J11a screenshot): a
    /// device count and the confirmation line, which a frozen sync cannot
    /// produce (the sync is frozen, so no push and no device fetch runs).
    /// Absent = not forced; production never sets them.
    var forcedDeviceCount: Int?
    var forcedJustSignedIn = false
    /// PR.13 fixtures for the two transport-failure states: offline (a passive
    /// "back online" row) and server-down (a 5xx, the "service unreachable"
    /// card with Try again). A frozen screenshot cannot run a real cycle, so
    /// these force the outcome a real transport would produce. Absent = not
    /// forced; production never sets them.
    var forcedOffline = false
    var forcedServerUnavailable = false
    /// P6.11 fixtures for a server that has moved ahead of this client (426,
    /// 402, unknown 4xx, 429): outcomes this app version can never provoke from
    /// a real server, so the only way to render them is to force them. Nil/
    /// absent = not forced; production never sets them.
    var forcedUpgradeRequired = false
    var forcedRefused: SyncServerError?
    var forcedRetryAfterSeconds: Int?
    /// RV.22 fixtures for the sync chip's presentation: force the chip state
    /// (and its label counts) directly so a screenshot or UI test can show each
    /// of the five states without reproducing the transport outcome that
    /// produces it. The mapping itself is L1-tested (`SyncChipTests`); these
    /// only let the L4 layer and screenshots drive the presentation. Nil/absent
    /// = derive from the real surface; production never sets them.
    var forcedChipState: SyncChipState?
    var forcedChipDirtyCount: Int?
    var forcedChipFlaggedCount: Int?

    init(sessionStore: any SessionStore = KeychainSessionStore(),
         configService: AppConfigService,
         powerState: any PowerStateProvider = ProcessInfoPowerState(),
         resumer: LowPowerResumer? = nil) {
        self.sessionStore = sessionStore
        self.configService = configService
        self.powerState = powerState
        let resumer = resumer ?? LowPowerResumer(powerState: powerState)
        self.resumer = resumer
        Task { await resumer.start() }
        // The surface must re-render the instant the mode changes: when Low
        // Power turns on the row gains the reason, when it ends the reason
        // vanishes (and the resumer drains what was deferred). The resumer and
        // this observer listen to the same change - one drains, one re-draws.
        powerChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    var signedIn: Bool { session != nil }

    /// Whether the account card should show the J11a confirmation line
    /// ("Your garage now follows your account"). The real flag comes from the
    /// sign-in flow's first push; the fixture lets a frozen-sync screenshot
    /// render the just-signed-in card.
    var justSignedIn: Bool { didJustSignIn || forcedJustSignedIn }

    /// The device count for the account card's "· N device(s)" suffix, or nil
    /// while unknown (guest, offline, or the fetch failed). The fixture lets a
    /// frozen-sync screenshot render the count.
    var deviceCount: Int? { forcedDeviceCount ?? fetchedDeviceCount }

    var surfaceState: SyncSurfaceState {
        SyncSurfaceState(
            isSignedIn: signedIn,
            lastSyncDate: lastSyncDate,
            dirtyCount: dirtyCount,
            offline: forcedOffline || (lastOutcome?.offline ?? false),
            serverUnavailable: forcedServerUnavailable
                || (lastOutcome?.serverUnavailable ?? false),
            deviceRevoked: forcedRevoked || (lastOutcome?.deviceRevoked ?? false),
            authExpired: storedAuthExpired || (lastOutcome?.authExpired ?? false),
            quotaUsedPercent: forcedQuotaPercent,
            flaggedCount: flaggedCount,
            isSyncing: isSyncing,
            // P6.8: the reason is on whenever the mode is; the S7 row names it
            // only when a queue is actually waiting (SyncSurface.lowPowerReason).
            lowPowerModeDeferring: powerState.isLowPowerModeEnabled
        )
    }

    var status: SyncStatus { SyncSurface.status(surfaceState) }

    /// RV.22: which Settings card the sync chip's Settings tap should scroll to.
    /// The chip sets this just before it pushes Settings; `SettingsView` scrolls
    /// to the named card and clears it. Nil for the gear and for states 3-5, so
    /// only a chip tap on an attention state (the only states with a named fix)
    /// scrolls. Transient UI intent, not sync state - never persisted, never
    /// logged.
    var settingsScrollTarget: SettingsScrollTarget?

    /// Whether the last cycle ended with an expired session whose refresh was
    /// rejected (PR.1), or the persisted mark says the session is expired
    /// (RV.26 - the cloud gateway sets the same mark on its own 401). The
    /// account card shows the re-sign-in card for this, never "update the app".
    var authExpired: Bool { storedAuthExpired || (lastOutcome?.authExpired ?? false) }

    /// The server-ahead notice the Settings account card surfaces: the forced
    /// fixture when a seed set one, else the coordinator's last outcome. It is
    /// the one place `SyncOutcome.upgradeRequired` / `refusedByServer` /
    /// `retryAfterSeconds` become visible - the P6.11 defect was that nothing
    /// read them.
    var serverNotice: SyncServerNotice {
        if forcedUpgradeRequired { return .upgradeRequired }
        if let forcedRefused {
            switch forcedRefused {
            case .tierRefused:
                return .tierRefused
            case .rateLimited(let retryAfter):
                return .rateLimited(retryAfterSeconds: forcedRetryAfterSeconds ?? retryAfter)
            case .refused(let status):
                return .refused(status: status)
            default:
                break
            }
        }
        guard let outcome = lastOutcome else { return .none }
        return SyncServerNotice.classify(outcome)
    }

    private func coordinator() -> SyncCoordinator? {
        if let core { return core }
        guard let repository = try? AppStore.repository() else { return nil }
        let coordinator = SyncService.makeCoordinator(repository: repository,
                                                      sessionStore: sessionStore,
                                                      powerState: powerState)
        core = coordinator
        return coordinator
    }

    /// Reads the session, the derived counts and the coordinator's last outcome.
    /// Cheap and pure - called on appear and after every sync.
    func refresh() async {
        session = try? sessionStore.load()
        storedAuthExpired = (try? sessionStore.isAuthExpired()) ?? false
        if session == nil {
            // The account is gone; the just-signed-in confirmation must not
            // outlive the session it confirmed.
            didJustSignIn = false
        }
        if let core {
            lastSyncDate = core.lastSyncDate()
            lastOutcome = core.lastOutcome()
        }
        // The "· N device(s)" suffix on the reassurance line (docs/JOURNEYS.md
        // J11a). Best-effort: a guest, an offline device or a fetch failure
        // leaves the count nil and the card shows the plain status line.
        fetchedDeviceCount = nil
        if session != nil {
            fetchedDeviceCount = try? await accountDevicesClient().devices().count
        }
        do {
            let repository = try AppStore.repository()
            dirtyCount = (try? repository.fetchDirtyRows().count) ?? 0
            flaggedCount = (try? repository.flaggedEntryCount()) ?? 0
        } catch {
            dirtyCount = 0
            flaggedCount = 0
        }
    }

    /// PJ.13 (docs/JOURNEYS.md J11a -> First push): the user-initiated cycle
    /// the sign-in flow runs before finishing. Marks the account as just
    /// signed in, then runs the ONE coordinator with a `.userInitiated`
    /// trigger - never `.background`, which LowPowerPolicy defers while Low
    /// Power Mode is on.
    ///
    /// Deliberately does NOT update this surface's state. The Settings card
    /// must learn about the new session from its own refresh on sheet
    /// dismissal - a `.sheet` does not re-trigger the presenter's `.task` on
    /// iOS 26 (the P6.18b finding, pinned by a UI test), so the dismissal
    /// refresh is what makes the card reflect the sign-in. The coordinator
    /// instance is the same one Settings reads, so that refresh sees this
    /// push's outcome.
    @discardableResult
    func firstPushNow() async -> SyncOutcome {
        didJustSignIn = true
        guard !isSyncing, configService.allowsServerBacked, let coordinator = coordinator() else {
            return SyncOutcome()
        }
        return await coordinator.syncNow(trigger: .userInitiated)
    }

    /// The host-bound account client for the card's device count - the same
    /// endpoint the Account & devices screen uses, over the app's transport
    /// selection (offline under a seeded launch, the sign-in stub under a UI
    /// test that must see the count).
    ///
    /// Built WITHOUT the session refresher on purpose: the count is a secondary
    /// display detail, so a stale token must read as "count unknown", never as
    /// a refresh attempt that clears the session out from under the sync's own
    /// auth path (a 401 here maps straight to `.unauthorized` and the card
    /// shows the plain status line).
    private func accountDevicesClient() -> AccountClient {
        AccountClient(
            httpClient: TankbookHTTPClient(
                transport: makeAppTransport(),
                tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
            director: AppConfigStore.shared.director)
    }

    /// The manual trigger. Idempotency is the coordinator's guarantee (the push
    /// count, not this flag); `isSyncing` only drives the spinner.
    ///
    /// Under `.required` (P6.18b) the trigger is a no-op: the server has
    /// stopped supporting this build, so the push would be refused anyway
    /// (426), and the sync surface renders the non-dismissible update notice
    /// instead of this affordance. The queue stays dirty (S7) - nothing is
    /// lost, nothing is claimed.
    func syncNow() async {
        await runSync(trigger: .userInitiated)
    }

    /// Signs this device out (RV.40, docs/SYNC.md -> "Sign out"). Two steps in
    /// the existing `SessionSignOut` order: revoke the refresh chain server-side
    /// (`DELETE /auth/session`, best-effort - a handed-over phone must not keep
    /// a 90-day chain valid) and clear the Keychain unconditionally (offline
    /// sign-out still signs out locally, hard rule 1). It is NOT a device
    /// revoke: the device row survives, so a later sign-in reuses it (RV.41).
    /// The local log is never touched - nothing here reads or writes the
    /// repository. After the clear, the surface re-reads the (now empty)
    /// session so the account card renders the guest state.
    func signOut() async {
        let store = sessionStore
        let authService: any AuthService = RemoteAuthService(
            director: AppConfigStore.shared.director,
            transport: makeAppTransport(),
            sessionStore: store,
            device: RemoteAuthService.SessionDevice(
                name: UIDevice.current.name,
                platform: "iOS"
            )
        )
        await SessionSignOut(authService: authService, sessionStore: store).signOut()
        await refresh()
    }

    /// The launch / foreground / timer cycle (docs/SYNC.md -> Low Power Mode:
    /// "opportunistic sync cycles (launch, foreground, timer)"). Passes
    /// `.background`, so the cycle defers while the mode is on - the queue is
    /// exactly as it was (hard rule 8) - and the deferred cycle is registered
    /// with the resumer, which drains it the moment the mode ends. The ONLY
    /// callers are app-scheduled events; a sync the user tapped goes through
    /// `syncNow()`. A guest has nothing to sync, so the cycle is a no-op until
    /// there is an account.
    ///
    /// RV.18: rate-limited by `OpportunisticSyncPolicy` - a burst of `.active`
    /// transitions (the launch double-fire, a permission-alert dismissal, the
    /// Photos picker) is one cycle, not one each. The Settings "Sync now" tap,
    /// the retry backoff and the Low Power resumer drain never come through
    /// this door, so a forced cycle is always available.
    func runOpportunisticSync() async {
        session = try? sessionStore.load()
        guard signedIn else { return }
        let now = Date()
        guard OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: lastOpportunisticSyncAt,
                                                now: now) else { return }
        lastOpportunisticSyncAt = now
        await runSync(trigger: .background)
    }

    private func runSync(trigger: PowerWorkTrigger) async {
        guard !isSyncing, configService.allowsServerBacked, let coordinator = coordinator() else { return }
        isSyncing = true
        defer { isSyncing = false }
        let outcome = await coordinator.syncNow(trigger: trigger)
        if outcome.deferred {
            registerDeferredSync()
        }
        // RV.18: observe that the door was knocked and how many cycles have
        // actually fired per trigger. Shape-only - the trigger name and running
        // counts are loggable, domain values are not (hard rule 12).
        let counts = coordinator.cycleCounts()
        AppLog.shared.emit(SyncCycleFired(
            trigger: trigger.name,
            backgroundCount: counts.background,
            userInitiatedCount: counts.userInitiated))
        await refresh()
        // PR.14: the post-batch toast count. A batch that flagged nothing
        // clears any earlier count; the toast is about what just arrived.
        lastBatchFlaggedEntries = outcome.flaggedEntries > 0 ? outcome.flaggedEntries : nil
    }

    /// Clears the post-batch toast once the user taps through to the flagged
    /// entries (the toast's next step, docs/SYNC.md).
    func acknowledgeFlaggedBatch() {
        lastBatchFlaggedEntries = nil
    }

    /// P6.8: records the deferred cycle with the resumer so it drains on the
    /// power-state change, not at next launch (docs/SYNC.md). The id is stable,
    /// so a second deferral replaces the first registration - the queue drains
    /// once. The drain re-runs the SAME background trigger, so a mode that
    /// merely toggles re-defers cleanly.
    private func registerDeferredSync() {
        let work = LowPowerResumer.PendingWork(id: Self.deferredSyncID, kind: .syncCycle) {
            await self.runDeferredSync()
        }
        Task { await resumer.register(work) }
    }

    private func runDeferredSync() async {
        await runSync(trigger: .background)
    }
}

/// The app's one transport selection (P6.21): under a DEBUG seeded launch the
/// transport is offline/deterministic, and in release it is always the real
/// URLSession transport - the seed transports never ship.
func makeAppTransport() -> any TankbookHTTPTransport {
    #if DEBUG
    return SeededLaunch.transport()
    #else
    return URLSessionTransport()
    #endif
}

/// RV.22: the Settings card the sync chip's Settings tap should scroll to
/// (docs/SYNC.md -> "The sync state chip", state 2: "Settings, scrolled to the
/// card naming the fix"). Each attention reason maps to the card that names its
/// next step; `account` is the auth-expired card (rendered in the account card's
/// signed-out branch), `revokedCard` and `quotaCard` the two issue cards below.
enum SettingsScrollTarget: Hashable, Sendable {
    case account
    case revokedCard
    case quotaCard
}
