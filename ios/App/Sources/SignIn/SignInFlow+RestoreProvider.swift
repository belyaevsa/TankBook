import Foundation
import TankbookCore

extension SignInFlow {
    /// The real restore provider: `RestoreEngine` over a `SyncEngine` pulling
    /// from a fresh cursor (0 - restore and incremental catch-up are the same
    /// call, docs/API.md). Every advance is persisted through to the device
    /// store as the pull earns it, so the app's regular sync continues
    /// incrementally where the restore left off even mid-cycle.
    @MainActor
    static func makeRestoreProvider(sessionStore: any SessionStore) -> any RestoreProviding {
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
            transport: appTransport(URLSessionTransport()),
            tokenProvider: tokenProvider,
            refresher: AppSessionRefresher.shared
        )
        // Restore always pulls from 0, never from a stale account's cursor - but
        // the advance is written through to the durable store at the pull that
        // earned it, so the app's regular sync (which runs on its own in-flight
        // gate) reads the restore's progress instead of re-fetching the delta.
        // RV.249: the durable store is keyed by the account being restored, so
        // the write-through never lands on another account's cursor.
        let cursor = SeededSyncCursorStore(seed: 0,
                                           persistingTo: UserDefaultsSyncCursorStore(accountId: accountId))
        let engine = SyncEngine(
            repository: repository,
            transport: transport,
            cursorStore: cursor,
            payloadMemory: InMemorySyncPayloadMemory(),
            log: AppLog.shared
        )
        return await RestoreEngine(engine: engine).restore()
    }
}
