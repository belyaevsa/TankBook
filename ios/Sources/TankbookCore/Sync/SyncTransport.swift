import Foundation

/// The network seam for the sync engine (docs/TESTING.md: "the network must be
/// an injected protocol"). The production implementation is
/// `RemoteSyncTransport`; tests use a deterministic in-memory double.
public protocol SyncTransport: Sendable {
    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse
    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse
}

/// Where the pull cursor lives (docs/SYNC.md: "cursor stored per device, only
/// after applying the page"). The real implementation is
/// `UserDefaultsSyncCursorStore`; tests use an in-memory double.
public protocol SyncCursorStore: Sendable {
    func load() throws -> Int64?
    func save(_ cursor: Int64) throws
}

/// Remembers each record's last-synced payload so a `Vehicle` edit can be
/// diffed field-by-field (docs/SYNC.md: per-field `updatedAt`). The engine asks
/// this store before pushing a dirty `Vehicle`; after a successful push or pull
/// it records the payload that now represents the server's state.
public protocol SyncPayloadMemory: Sendable {
    func lastSyncedPayload(for id: UUID) -> JSONValue?
    func recordSynced(id: UUID, payload: JSONValue)
}

/// A `SyncCursorStore` backed by `UserDefaults`, keyed by account id. The cursor
/// is an opaque monotonic integer - not sensitive - so a plain preference slot is
/// the right home (docs/SCHEMA.md: "sync cursor & auth tokens - infrastructure").
///
/// The key carries the account id because one device can hold cursors for more
/// than one account: sign-out clears the session, never the cursor, so an
/// unkeyed cursor would let a later sign-in to a different account resume from
/// the previous account's SCN and skip its history (RV.249). The per-account key
/// is also what makes the monotonic guard safe: `save` ignores a lower advance
/// for the same account, while a different account reads its own slot (a restore
/// still seeds 0 by design - `SeededSyncCursorStore`).
public struct UserDefaultsSyncCursorStore: SyncCursorStore {
    private let accountId: String
    /// The pre-RV.249 unkeyed key, migrated into the account's slot on first
    /// load and then deleted. The per-account key is derived from it.
    private let legacyKey: String
    /// An explicit suite name, when the caller must not touch `.standard` (a
    /// test uses an ephemeral suite and tears it down). `UserDefaults` itself is
    /// not `Sendable`, so the store resolves it from the suite name at each call
    /// rather than holding one - the same shape as `UserDefaultsSyncStateStore`.
    private let suiteName: String?

    public init(accountId: String,
                legacyKey: String = "tankbook.sync.cursor",
                suiteName: String? = nil) {
        self.accountId = accountId
        self.legacyKey = legacyKey
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private var key: String { "\(legacyKey).\(accountId)" }

    public func load() throws -> Int64? {
        if let value = defaults.object(forKey: key) as? Int64 { return value }
        // RV.249 migration: before this key existed, one device held one cursor
        // for whoever was signed in. Move it into the signed-in account's slot
        // once, then delete the old key so a later account cannot inherit it.
        guard let legacy = defaults.object(forKey: legacyKey) as? Int64 else { return nil }
        defaults.set(legacy, forKey: key)
        defaults.removeObject(forKey: legacyKey)
        return legacy
    }

    public func save(_ cursor: Int64) throws {
        // Monotonic per account: an in-flight restore page can return a lower
        // `nextSince` than the app engine already persisted, and that lower
        // advance is a stale replay, never a real step back - SCN only moves
        // forward for a given account.
        if let current = defaults.object(forKey: key) as? Int64, cursor < current { return }
        defaults.set(cursor, forKey: key)
        // A write-through `save` can run before this account's first `load`
        // (a restore). Delete the legacy key here too, so it cannot linger and
        // later migrate into a different account.
        defaults.removeObject(forKey: legacyKey)
    }
}

/// A cursor store that starts a session at a fixed `seed` but persists every
/// advance through to a durable store the moment it is saved.
///
/// A restore must pull from 0 even when the durable cursor still holds a
/// previous account's value, so `load` answers the seed and never the durable
/// value. But the advance belongs to the pull that earned it, not to the end of
/// the surrounding cycle: a process restart immediately after the pull must
/// resume from it, and a second engine sharing `durable` (the app's regular
/// sync, which runs on its own in-flight gate) must read it before the first
/// cycle's push finishes. Buffering the advance until the cycle ends is what
/// let a slow push hold the window open for the second pass to re-fetch the
/// delta the restore had already pulled.
public final class SeededSyncCursorStore: SyncCursorStore, @unchecked Sendable {
    private let durable: any SyncCursorStore
    private let lock = NSLock()
    private var value: Int64

    public init(seed: Int64 = 0, persistingTo durable: any SyncCursorStore) {
        self.durable = durable
        self.value = seed
    }

    public func load() throws -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func save(_ cursor: Int64) throws {
        lock.lock()
        value = cursor
        lock.unlock()
        try durable.save(cursor)
    }
}

/// An in-memory `SyncCursorStore` - the test double, and the session-scoped
/// default until a device-level store is wired.
public final class InMemorySyncCursorStore: SyncCursorStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64?

    public init() {}

    public func load() throws -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func save(_ cursor: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        value = cursor
    }
}

/// An in-memory `SyncPayloadMemory` - the test double. Session-scoped: a fresh
/// engine instance starts with no last-synced payloads, which degrades
/// field-level merge to "every field changed at the write time" for the first
/// sync of the session (documented in docs/SYNC.md).
public final class InMemorySyncPayloadMemory: SyncPayloadMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [UUID: JSONValue] = [:]

    public init() {}

    public func lastSyncedPayload(for id: UUID) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        return payloads[id]
    }

    public func recordSynced(id: UUID, payload: JSONValue) {
        lock.lock(); defer { lock.unlock() }
        payloads[id] = payload
    }
}
