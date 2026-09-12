import Foundation

/// The failure classes a sync cycle can end in, exactly the set `SyncOutcome`
/// can produce (OB.3). A **deferred** or **inert** cycle is not a failure and
/// has no case here - same reasoning as `SyncCycleCounts`
/// (SyncCoordinator.swift): neither fired. `invalidResponse` mirrors the
/// undecodable-body wire class (`SyncServerError.invalidResponse`); the engine
/// folds an undecodable body into the `serverUnavailable` outcome today, so a
/// cycle that ends that way persists as `.serverUnavailable` with nil code and
/// nil traceId - the record still carries everything OB.4's export needs.
public enum SyncFailureKind: String, Codable, Sendable, Equatable {
    case offline
    case serverUnavailable
    case authExpired
    case deviceRevoked
    case upgradeRequired
    case tierRefused
    case rateLimited
    case refused
    case invalidResponse
}

extension SyncFailureKind {
    /// The single classification of a cycle outcome into a recordable failure
    /// class (OB.3). One place, so no second classifier can drift from what
    /// `SyncServerNotice.classify` surfaces: the refusal subclasses mirror the
    /// outcome's `refusedByServer`, and the transport classes mirror its flags.
    /// Nil means the cycle did not fail - a success, a deferral, or an inert
    /// repeat - and is therefore not recordable.
    public init?(outcome: SyncOutcome) {
        if outcome.deviceRevoked { self = .deviceRevoked; return }
        if outcome.authExpired { self = .authExpired; return }
        if outcome.upgradeRequired { self = .upgradeRequired; return }
        if outcome.offline { self = .offline; return }
        if outcome.serverUnavailable { self = .serverUnavailable; return }
        switch outcome.refusedByServer {
        case .tierRefused: self = .tierRefused
        case .rateLimited: self = .rateLimited
        case .refused: self = .refused
        default: return nil
        }
    }
}

/// One recorded failure: when it happened, the class, and - when the server
/// answered with a problem+json body - the raw `code` and `traceId` OB.1 put on
/// the wire (docs/API.md -> Error envelope). The code is stored raw, never
/// classified again, so a newer server's code survives intact for OB.4's
/// export. Infrastructure only: a class, a timestamp, a code, a trace id -
/// no domain value (hard rule 12).
public struct SyncFailureRecord: Codable, Sendable, Equatable {
    public let at: Date
    public let kind: SyncFailureKind
    public let code: String?
    public let traceId: String?

    public init(at: Date, kind: SyncFailureKind, code: String?, traceId: String?) {
        self.at = at
        self.kind = kind
        self.code = code
        self.traceId = traceId
    }
}

/// The device-scoped sync state that survives a relaunch (OB.3): when the last
/// non-inert cycle succeeded and, separately, the last failure. `lastSuccessAt`
/// is left alone by a failing cycle and only ever moved forward by a success;
/// `lastFailure` is cleared by a success. Nothing else may be added - the
/// record is infrastructure and contains no domain value (hard rule 12).
public struct PersistedSyncState: Codable, Sendable, Equatable {
    public var lastSuccessAt: Date?
    public var lastFailure: SyncFailureRecord?

    public init(lastSuccessAt: Date?, lastFailure: SyncFailureRecord?) {
        self.lastSuccessAt = lastSuccessAt
        self.lastFailure = lastFailure
    }
}

/// Where the persisted sync state lives (OB.3). The production implementation
/// is `UserDefaultsSyncStateStore`; tests use `InMemorySyncStateStore`.
public protocol SyncStateStore: Sendable {
    func load() -> PersistedSyncState
    func save(_ state: PersistedSyncState)
}

/// A `SyncStateStore` backed by `UserDefaults`, JSON under a key. The state
/// is a timestamp, a class, a code and a trace id - infrastructure, not
/// sensitive - so a plain preference slot is the right home (docs/SCHEMA.md:
/// "sync cursor & auth tokens - infrastructure"; the same reasoning as
/// `UserDefaultsSyncCursorStore`, and hard rule 12: no domain value ever rides
/// here). The `UserDefaults` is injectable so a test never touches `.standard`.
///
/// The key carries the account id because one device can hold sync state for
/// more than one account: sign-out clears the session, never the state, so an
/// unkeyed store would render account A's last success and last failure on
/// account B's card until B's first cycle overwrote them (RV.256). The keyed
/// slot is the same shape that keeps `UserDefaultsSyncCursorStore` from
/// resuming a different account's pull.
public struct UserDefaultsSyncStateStore: SyncStateStore {
    private let accountId: String
    /// The pre-RV.256 unkeyed key, migrated into the account's slot on first
    /// load and then deleted. The per-account key is derived from it.
    private let legacyKey: String
    /// An explicit suite name, when the caller must not touch `.standard` (a
    /// test uses an ephemeral suite and tears it down). `UserDefaults` itself
    /// is not `Sendable`, so the store resolves it from the suite name at each
    /// call rather than holding one - the same shape that keeps
    /// `UserDefaultsSyncCursorStore` Sendable.
    private let suiteName: String?

    public init(accountId: String,
                legacyKey: String = "tankbook.sync.state",
                suiteName: String? = nil) {
        self.accountId = accountId
        self.legacyKey = legacyKey
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private var key: String { "\(legacyKey).\(accountId)" }

    public func load() -> PersistedSyncState {
        if let data = defaults.data(forKey: key),
           let state = try? JSONDecoder.syncState.decode(PersistedSyncState.self, from: data) {
            return state
        }
        // RV.256 migration: before this key existed, one device held one state
        // for whoever was signed in. Move it into the signed-in account's slot
        // once, then delete the old key so a later account cannot inherit it.
        guard let legacy = defaults.data(forKey: legacyKey),
              let state = try? JSONDecoder.syncState.decode(PersistedSyncState.self, from: legacy) else {
            return PersistedSyncState(lastSuccessAt: nil, lastFailure: nil)
        }
        defaults.set(legacy, forKey: key)
        defaults.removeObject(forKey: legacyKey)
        return state
    }

    public func save(_ state: PersistedSyncState) {
        guard let data = try? JSONEncoder.syncState.encode(state) else { return }
        defaults.set(data, forKey: key)
        // A write-through `save` can run before this account's first `load`.
        // Delete the legacy key here too, so it cannot linger and later migrate
        // into a different account.
        defaults.removeObject(forKey: legacyKey)
    }
}

/// The in-memory `SyncStateStore` - the test double, and the default a
/// coordinator without an injected store keeps (so an un-wired embedding
/// behaves exactly as it did before OB.3: nothing persisted).
public final class InMemorySyncStateStore: SyncStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state = PersistedSyncState(lastSuccessAt: nil, lastFailure: nil)

    public init() {}

    public init(seededWith state: PersistedSyncState) {
        self.state = state
    }

    public func load() -> PersistedSyncState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public func save(_ state: PersistedSyncState) {
        lock.lock(); defer { lock.unlock() }
        self.state = state
    }
}

extension JSONEncoder {
    /// The encoder `UserDefaultsSyncStateStore` round-trips with: ISO-8601 so
    /// the stored JSON reads as timestamps, not opaque reference-date seconds.
    fileprivate static let syncState: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    fileprivate static let syncState: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
