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

/// A `SyncCursorStore` backed by `UserDefaults`. The cursor is an opaque
/// monotonic integer - not sensitive - so a plain preference slot is the right
/// home (docs/SCHEMA.md: "sync cursor & auth tokens - infrastructure").
public struct UserDefaultsSyncCursorStore: SyncCursorStore {
    private let key: String

    public init(key: String = "tankbook.sync.cursor") {
        self.key = key
    }

    public func load() throws -> Int64? {
        guard let value = UserDefaults.standard.object(forKey: key) as? Int64 else { return nil }
        return value
    }

    public func save(_ cursor: Int64) throws {
        UserDefaults.standard.set(cursor, forKey: key)
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
