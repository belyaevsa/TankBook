import Foundation

/// The result of one sync cycle (docs/SYNC.md, S1-S9). Counts and flags only -
/// no domain values (hard rule 12).
public struct SyncOutcome: Equatable, Sendable {
    public var pulled = 0
    public var pushed = 0
    public var conflictsResolved = 0
    public var flaggedEntries = 0
    /// The number of rows the server rejected structurally this cycle
    /// (`payload_schema_violation` et al., RV.284). Each is marked `rejected`
    /// and stops re-pushing until the record is edited again - a 422 is not
    /// unavailability, the same bytes would be rejected forever (S7's 422
    /// sibling).
    public var rejected = 0
    public var clampedIds: [UUID] = []
    public var deviceRevoked = false
    /// The access token expired and the refresh failed (PR.1): the session is
    /// gone and the user signs in again. Distinct from `deviceRevoked` (a 410
    /// from the server) and from `offline`/`serverUnavailable` (an outage the
    /// app retries itself). Nothing is lost - rows stay dirty (S7).
    public var authExpired = false
    public var upgradeRequired = false
    /// The host could not be reached (no network, DNS failure, connection
    /// refused): the device is offline. Passive - the honest next step is
    /// "will sync when you're back online" (docs/ERRORS.md -> Settings), never
    /// an error. Nothing is lost - rows stay dirty (S7).
    public var offline = false
    /// The host answered 5xx: the server is up but failing. Distinct from
    /// `offline` because the honest next step differs: a 5xx names the service
    /// being down with "try again", where offline is a passive "back online"
    /// (docs/ERRORS.md -> Settings). Nothing is lost either way - rows stay
    /// dirty (S7).
    public var serverUnavailable = false
    /// A `402`/unknown-4xx refusal from a server newer than this client, or a
    /// `429` wait. Distinct from `offline`/`serverUnavailable` because the
    /// honest next step differs: an outage resolves itself, a refusal needs a
    /// newer app (P6.11). `retryAfterSeconds` carries the server's own hint
    /// when it sent one. Nothing is lost either way - the rows stay dirty (S7).
    public var refusedByServer: SyncServerError?
    public var retryAfterSeconds: Int?
    /// RV.253: the blob pipeline's quota state - the percent the server's 429
    /// carried, or 100 when it carried none (exceeded IS full). Nil when no
    /// attachment hit the quota this cycle, which is also what clears the
    /// Settings card on a later successful cycle. Counts only - no domain value
    /// (hard rule 12).
    public var quotaUsedPercent: Int?
    /// P6.8: the cycle was postponed because Low Power Mode is on and this was
    /// opportunistic work (docs/SYNC.md -> Low Power Mode). Nothing ran, the
    /// dirty queue is exactly as it was, and the work drains when the mode
    /// ends - resume, not next launch.
    public var deferred = false

    public init() {}
}

extension SyncOutcome {
    /// Splits the transport failure into the two PR.13 states, made where the
    /// transport failure is actually known: `offline` is the one case where the
    /// host never answered; every other error (a 5xx, an undecodable body, a
    /// pull-side refusal) means the host answered and the service is down, so it
    /// folds into `serverUnavailable`. Kept on the outcome so `SyncEngine`'s
    /// catch ladder stays below the cyclomatic-complexity budget.
    mutating func applyTransportFailure(_ error: any Error) {
        if case SyncServerError.offline = error {
            offline = true
        } else {
            serverUnavailable = true
        }
    }
}
