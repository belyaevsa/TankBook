import Foundation
import Observation
import TankbookCore

/// Builds the app's one `SyncCoordinator` over the real repository, transport
/// and session store (docs/SYNC.md: one sync path - the trigger and the
/// transport live here, nothing else constructs a second `SyncEngine`).
@MainActor
enum SyncService {
    static func makeCoordinator(repository: TankbookRepository,
                                sessionStore: any SessionStore,
                                powerState: any PowerStateProvider) -> SyncCoordinator {
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.live")!
        let tokenProvider = KeychainTokenProvider(sessionStore: sessionStore)
        let transport = RemoteSyncTransport(
            baseURL: baseURL,
            transport: URLSessionTransport(),
            tokenProvider: tokenProvider
        )
        // P4.6: the blob gate hooks attachments into the push loop - a live
        // attachment record uploads its rendition (begin -> PUT -> commit)
        // before it pushes, and defers otherwise (docs/SYNC.md, upload step 5).
        let blobGate = LocalFileBlobPushGate(
            uploader: BlobUploader(transport: RemoteBlobTransport(
                baseURL: baseURL, transport: URLSessionTransport(), tokenProvider: tokenProvider)),
            source: FileBackedBlobSource(directory: (try? VehiclePhotoStore.attachmentsDirectory()) ?? FileManager.default.temporaryDirectory)
        )
        let engine = SyncEngine(
            repository: repository,
            transport: transport,
            cursorStore: UserDefaultsSyncCursorStore(),
            payloadMemory: InMemorySyncPayloadMemory(),
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
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.live")!
        let transport = RemoteBlobTransport(
            baseURL: baseURL,
            transport: URLSessionTransport(),
            tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)
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

    /// DEBUG/test fixtures for states a real transport never produces in a
    /// screenshot (410 device revoked, blob-quota 429, offline with a queue).
    /// Nil/absent = not forced; production never sets them.
    var forcedRevoked = false
    var forcedQuotaPercent: Int?
    var forcedTransportUnavailable = false
    /// P6.11 fixtures for a server that has moved ahead of this client (426,
    /// 402, unknown 4xx, 429): outcomes this app version can never provoke from
    /// a real server, so the only way to render them is to force them. Nil/
    /// absent = not forced; production never sets them.
    var forcedUpgradeRequired = false
    var forcedRefused: SyncServerError?
    var forcedRetryAfterSeconds: Int?

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

    var surfaceState: SyncSurfaceState {
        SyncSurfaceState(
            isSignedIn: signedIn,
            lastSyncDate: lastSyncDate,
            dirtyCount: dirtyCount,
            transportUnavailable: forcedTransportUnavailable
                || (lastOutcome?.transportUnavailable ?? false),
            deviceRevoked: forcedRevoked || (lastOutcome?.deviceRevoked ?? false),
            quotaUsedPercent: forcedQuotaPercent,
            flaggedCount: flaggedCount,
            isSyncing: isSyncing,
            // P6.8: the reason is on whenever the mode is; the S7 row names it
            // only when a queue is actually waiting (SyncSurface.lowPowerReason).
            lowPowerModeDeferring: powerState.isLowPowerModeEnabled
        )
    }

    var status: SyncStatus { SyncSurface.status(surfaceState) }

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
        if let core {
            lastSyncDate = core.lastSyncDate()
            lastOutcome = core.lastOutcome()
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

    /// The launch / foreground / timer cycle (docs/SYNC.md -> Low Power Mode:
    /// "opportunistic sync cycles (launch, foreground, timer)"). Passes
    /// `.background`, so the cycle defers while the mode is on - the queue is
    /// exactly as it was (hard rule 8) - and the deferred cycle is registered
    /// with the resumer, which drains it the moment the mode ends. The ONLY
    /// callers are app-scheduled events; a sync the user tapped goes through
    /// `syncNow()`. A guest has nothing to sync, so the cycle is a no-op until
    /// there is an account.
    func runOpportunisticSync() async {
        session = try? sessionStore.load()
        guard signedIn else { return }
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
        await refresh()
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
