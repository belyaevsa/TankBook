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
    /// The name of the device that authored this record, when the server sends
    /// it (PR.14: it lets a losing device attribute the overwrite in the
    /// "Changed by sync" row). Forward-compatible: nil when the wire omits it,
    /// so an older backend simply leaves the overwrite unattributed.
    public var originDeviceName: String?

    public init(id: UUID, entityType: String, schemaVersion: Int, scn: Int64,
                payload: JSONValue, clientUpdatedAt: Date, deleted: Bool,
                originDeviceName: String? = nil) {
        self.id = id
        self.entityType = entityType
        self.schemaVersion = schemaVersion
        self.scn = scn
        self.payload = payload
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
        self.originDeviceName = originDeviceName
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
    /// The access token expired and the refresh failed (the refresh token was
    /// rejected). The session is gone; the user signs in again. This is an auth
    /// event, never an unknown gate from a newer server (PR.1 - never "update
    /// the app").
    case authExpired
    /// `426`: the push batch is refused because the client's schema version is
    /// below the server's minimum. Pull still works - never lock a user out.
    case upgradeRequired
    /// The host could not be reached (no network, DNS failure, connection
    /// refused, timeout): the device is offline. S7: nothing is lost, rows
    /// return to `dirty`. Distinct from `serverUnavailable` because the honest
    /// next step differs (docs/ERRORS.md -> Settings): offline is a passive
    /// "will sync when you're back online", a 5xx names the service being down.
    case offline
    /// The host answered 5xx: the server is up but failing. S7: nothing is
    /// lost, rows return to `dirty`. Distinct from `offline` for the same
    /// reason the two next steps differ.
    case serverUnavailable
    /// The gateway's lumped "transport failure or 5xx" case (docs/API.md ->
    /// "LLM gateway"). The extract client does not need the split: its next
    /// step is the same either way (the on-device result stands, F4). The sync
    /// transport throws `offline` / `serverUnavailable` instead.
    case transportUnavailable
    /// The server answered but the body could not be decoded.
    case invalidResponse
    /// `402`: the server gated this on a tier or capability THIS CLIENT does not
    /// have. There is no Pro tier today - every user has full access - so the
    /// only way a shipped client sees this is a server that has moved ahead of
    /// it, which makes the honest reading "this app is out of date", not "buy
    /// something" (hard rule 7: monetization appears in no error surface but the
    /// car-limit sheet). Nothing is lost: the push is refused, the rows stay
    /// dirty, and the pull is unaffected.
    case tierRefused
    /// `429`: rate- or quota-limited for this period, with the server's
    /// `Retry-After` in seconds when it sent one. A wait, not a failure.
    case rateLimited(retryAfterSeconds: Int?)
    /// Any other 4xx: a gate this client version does not know about. Kept
    /// DISTINCT from `invalidResponse` on purpose - "the body could not be
    /// decoded" is a lie about a response that decoded perfectly well and simply
    /// said no, and a generic failure message is what JOURNEYS F7 forbids.
    case refused(status: Int)
}
