import Foundation
import Observation
import TankbookCore

/// Builds the app's one `SyncCoordinator` over the real repository, transport
/// and session store (docs/SYNC.md: one sync path - the trigger and the
/// transport live here, nothing else constructs a second `SyncEngine`).
@MainActor
enum SyncService {
    static func makeCoordinator(repository: TankbookRepository,
                                sessionStore: any SessionStore) -> SyncCoordinator {
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.app")!
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
            blobGate: blobGate
        )
        return SyncCoordinator(engine: engine)
    }

    /// The lazy-download fetcher for opening an entry (docs/SYNC.md -> Delivery):
    /// nil when signed out - a guest never downloads, and the inline thumbnail
    /// still renders the chip. The fetch verifies the sha256 and caches forever
    /// after; a failure leaves the "photo syncing" shimmer, never an error.
    static func makeBlobFetcher(sessionStore: any SessionStore) -> LazyBlobFetcher? {
        guard (try? sessionStore.load()) != nil else { return nil }
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.app")!
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
    private var core: SyncCoordinator?

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

    init(sessionStore: any SessionStore = KeychainSessionStore()) {
        self.sessionStore = sessionStore
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
            isSyncing: isSyncing
        )
    }

    var status: SyncStatus { SyncSurface.status(surfaceState) }

    private func coordinator() -> SyncCoordinator? {
        if let core { return core }
        guard let repository = try? AppStore.repository() else { return nil }
        let coordinator = SyncService.makeCoordinator(repository: repository,
                                                      sessionStore: sessionStore)
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
    func syncNow() async {
        guard !isSyncing, let coordinator = coordinator() else { return }
        isSyncing = true
        defer { isSyncing = false }
        _ = await coordinator.syncNow()
        await refresh()
    }
}
