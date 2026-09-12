import Foundation
import TankbookCore

/// Builds the app's one `SyncCoordinator` over the real repository, transport
/// and session store (docs/SYNC.md: one sync path - the trigger and the
/// transport live here, nothing else constructs a second `SyncEngine`).
@MainActor
enum SyncService {
    static func makeCoordinator(repository: TankbookRepository,
                                sessionStore: any SessionStore,
                                accountId: String,
                                powerState: any PowerStateProvider) -> SyncCoordinator {
        let director = AppConfigStore.shared.director
        let tokenProvider = KeychainTokenProvider(sessionStore: sessionStore)
        let refresher = AppSessionRefresher.shared
        // OB.3: one diagnostics sink shared by the transport (which records the
        // wire code + traceId on a server answer) and the coordinator (which
        // clears it per cycle and persists it with a failure), and the device
        // store the sync state survives a relaunch in.
        let diagnostics = SyncFailureDiagnostics()
        let syncStateStore = UserDefaultsSyncStateStore()
        let transport = RemoteSyncTransport(
            director: director,
            transport: makeAppTransport(),
            tokenProvider: tokenProvider,
            refresher: refresher,
            diagnostics: diagnostics
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
            // RV.249: the cursor is keyed by account id. One device can hold
            // cursors for more than one account (sign-out clears the session,
            // never the cursor), and the keyed slot is what makes the store's
            // monotonic guard safe across an account switch.
            cursorStore: UserDefaultsSyncCursorStore(accountId: accountId),
            // PR.4: the payload memory is persisted, not in-memory: without it
            // the first sync claims every field changed and a stale device
            // reverts another device's edit (docs/SYNC.md S9, hard rule 13).
            payloadMemory: DatabaseSyncPayloadMemory(repository: repository),
            blobGate: blobGate,
            homeCurrencyRehomer: MoneyBackfillService(store: AppRates.store),
            powerState: powerState,
            log: AppLog.shared
        )
        return SyncCoordinator(engine: engine,
                               powerState: powerState,
                               syncStateStore: syncStateStore,
                               failureDiagnostics: diagnostics)
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
