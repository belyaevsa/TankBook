import Foundation

/// Decides when the Settings account card re-reads the account's device count
/// from `GET /account/devices` (docs/SYNC.md -> "The Settings sync surface":
/// the "Synced just now · N device(s)" reassurance suffix, docs/JOURNEYS.md
/// J11a). The value cached here is the LIVE device count - revoked rows are
/// returned marked and stay in the Account & devices list, but a revoked
/// device's next pull gets 410, so it cannot reach the account and does not
/// count (RV.54; the caller records `devices.liveDeviceCount`, never the raw
/// `count`).
///
/// RV.6 was that the decision did not exist: `AppSync.refresh()` re-fetched the
/// count on every call and never reused what it had, and `SettingsView`'s
/// `.task` calls `refresh()` on every appearance - so one "check my devices"
/// round trip (Settings appears -> push Account & devices -> pop back) cost a
/// devices GET at Settings and again on the pop-back, four GETs for gear ->
/// account -> back -> account, with no sync cycle involved.
///
/// The count is a reassurance detail and it changes on **events**, never on a
/// clock: a sign-in, a sign-out, a revoke and an account delete are the only
/// moments it can differ from what this cache holds. So this cache is reused
/// across every ordinary surface refresh and cleared only by those events.
/// Deliberately **not** a time interval (RV.6): an interval would make the
/// count *sometimes* stale for reasons the user cannot see, while event
/// invalidation keeps it correct on exactly the moments the user can act on.
/// A failed fetch leaves the count unknown (nil) so the next surface refresh
/// retries - a one-off failure never shows a stale cached value, and recovers
/// at the next appearance.
///
/// A pure decision (docs/TESTING.md L1), never the network: the caller
/// (`AppSync.refresh`) performs the fetch when the returned action says so and
/// reports the result through `record(_:)`.
public struct DeviceCountCache: Sendable, Equatable {
    /// The cached count, nil while unknown (never fetched, a fetch failed, or
    /// an event cleared it). The account card shows the plain status line while
    /// nil (docs/JOURNEYS.md J11a -> "Synced just now" without the suffix).
    public private(set) var count: Int?

    public init() {}

    /// What one surface refresh must do with the count. Decided here, in one
    /// place, so the app layer never re-decides it (the RV.6 defect was a
    /// second decision at the call site that disagreed with the cache).
    public enum Action: Sendable, Equatable {
        /// A session is present and the count is cached - issue no request.
        case reuse
        /// A session is present and the count is unknown - fetch it now.
        case fetch
        /// There is no session (sign-out, an account delete) - the count is
        /// forgotten with the account.
        case clear
    }

    /// The action for one surface refresh, applying the mutation the action
    /// itself carries: `.clear` forgets the count here and now; `.reuse` and
    /// `.fetch` leave the cache as it is. On `.fetch` the caller performs the
    /// request and reports the outcome through `record(_:)` (nil = failed).
    public mutating func refreshAction(signedIn: Bool) -> Action {
        guard signedIn else {
            count = nil
            return .clear
        }
        return count == nil ? .fetch : .reuse
    }

    /// Reports a fetch outcome. A non-nil count is cached for reuse; nil (the
    /// fetch failed) leaves the cache unknown so the next refresh retries. The
    /// value must be the LIVE count (`devices.liveDeviceCount`, RV.54) - the
    /// cache's `count` answers "how many devices can reach my data", so a caller
    /// that records the raw `devices().count` stores the RV.54 bug.
    public mutating func record(_ fetched: Int?) {
        count = fetched
    }

    /// An event changed the account's membership (a successful revoke, a
    /// sign-out, a sign-in, an account delete): the cached count is void and
    /// the next signed-in refresh must fetch again.
    public mutating func invalidate() {
        count = nil
    }
}
