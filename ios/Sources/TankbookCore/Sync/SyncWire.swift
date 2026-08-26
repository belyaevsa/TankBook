import Foundation

/// Wire shapes for the two sync endpoints (docs/API.md -> Sync). These mirror
/// the contract verbatim so the client and the in-memory transport double speak
/// the same language.

/// A pulled record (docs/API.md -> `GET /sync/pull`).
public struct SyncPullRecord: Equatable, Sendable {
    public var id: UUID
    public var entityType: String
    public var schemaVersion: Int
    public var scn: Int64
    public var payload: JSONValue
    public var clientUpdatedAt: Date
    public var deleted: Bool

    public init(id: UUID, entityType: String, schemaVersion: Int, scn: Int64,
                payload: JSONValue, clientUpdatedAt: Date, deleted: Bool) {
        self.id = id
        self.entityType = entityType
        self.schemaVersion = schemaVersion
        self.scn = scn
        self.payload = payload
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
    }

    /// Converts to the merge shape, reading any per-field versions the payload
    /// carries (docs/SYNC.md: `Vehicle` field-level merge).
    public func asRecord() -> SyncRecord {
        SyncRecord(
            id: id,
            entityType: entityType,
            schemaVersion: schemaVersion,
            payload: payload,
            clientUpdatedAt: clientUpdatedAt,
            deleted: deleted,
            fieldVersions: entityType == Vehicle.entityType ? VehicleFieldVersions.read(from: payload) : nil
        )
    }
}

/// The schema policy returned by pull (docs/API.md -> `schemaPolicy`).
public struct SyncSchemaPolicy: Equatable, Sendable {
    public var minSupported: Int
    public var current: Int

    public init(minSupported: Int, current: Int) {
        self.minSupported = minSupported
        self.current = current
    }
}

/// The `GET /sync/pull` response body.
public struct SyncPullResponse: Equatable, Sendable {
    public var records: [SyncPullRecord]
    public var nextSince: Int64
    public var more: Bool
    public var schemaPolicy: SyncSchemaPolicy

    public init(records: [SyncPullRecord], nextSince: Int64, more: Bool,
                schemaPolicy: SyncSchemaPolicy) {
        self.records = records
        self.nextSince = nextSince
        self.more = more
        self.schemaPolicy = schemaPolicy
    }
}

/// One change in a `POST /sync/push` batch (docs/API.md -> `POST /sync/push`).
public struct SyncPushChange: Equatable, Sendable {
    public var id: UUID
    public var entityType: String
    public var schemaVersion: Int
    /// 0 for new records; the server's SCN for an update.
    public var baseScn: Int64
    public var payload: JSONValue
    public var clientUpdatedAt: Date
    public var deleted: Bool

    public init(id: UUID, entityType: String, schemaVersion: Int, baseScn: Int64,
                payload: JSONValue, clientUpdatedAt: Date, deleted: Bool) {
        self.id = id
        self.entityType = entityType
        self.schemaVersion = schemaVersion
        self.baseScn = baseScn
        self.payload = payload
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
    }
}

/// The per-item outcome of a push (docs/API.md -> `POST /sync/push` results).
public struct SyncPushResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case accepted(newScn: Int64, clamped: Bool)
        case conflict(current: SyncPullRecord)
        case rejected(code: String, pointer: String?)
    }

    public var id: UUID
    public var status: Status

    public init(id: UUID, status: Status) {
        self.id = id
        self.status = status
    }
}

/// The `POST /sync/push` response body.
public struct SyncPushResponse: Equatable, Sendable {
    public var results: [SyncPushResult]

    public init(results: [SyncPushResult]) {
        self.results = results
    }
}

/// Server-level sync failures (docs/API.md -> Sync). The transport throws these;
/// the engine maps them to an outcome and never lets them lose local data.
public enum SyncServerError: Error, Equatable, Sendable {
    /// `410`: the device is revoked or the account is deleted. Local data stays
    /// local; the app re-onboards or detaches.
    case deviceRevoked
    /// `426`: the push batch is refused because the client's schema version is
    /// below the server's minimum. Pull still works - never lock a user out.
    case upgradeRequired
    /// The host could not be reached or the response was not HTTP-shaped. S7:
    /// nothing is lost, rows return to `dirty`.
    case transportUnavailable
    /// The server answered but the body could not be decoded.
    case invalidResponse
}
