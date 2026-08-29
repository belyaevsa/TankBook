import Foundation

/// The transport's timeout budgets, named once per tier (docs/PRACTICES.md U6,
/// §6 "Timeouts, backoff and poll intervals are operational"). Every value here
/// is a **compiled constant** on purpose: a remote-set 0 s timeout is a
/// remote-triggered outage, so transport timeouts may never be remote-configurable
/// (no `configPollInterval`-style key).
///
/// URLSessionConfiguration exposes exactly two timeouts and neither separates
/// connect from read:
/// - `timeoutIntervalForRequest` is the idle/read budget - it resets as data
///   arrives, and because no data arrives during a stalled TCP handshake it also
///   bounds the connect phase. A half-connected radio that never completes the
///   handshake therefore fails at this budget, not at the 60 s system default.
/// - `timeoutIntervalForResource` is the overall wall-clock cap for a resource.
///
/// There is no separate connect-timeout knob in URLSessionConfiguration, so a
/// distinct "connect 8 s" constant would be a number nothing reads. The read
/// budget below does that job: it caps both "connect never answered" and "bytes
/// stopped arriving".
public enum TransportTimeouts {
    /// Idle/read budget for ordinary JSON calls (sign-in, sync, rates, gateway,
    /// catalog, config). 30 s is short enough that a half-connected radio stops
    /// freezing a button at the 60 s default, long enough for a slow-but-alive
    /// response to arrive.
    public static let readJSON: TimeInterval = 30

    /// Budget the long paths ask for explicitly (per-request override on
    /// `TankbookHTTPRequest.timeoutInterval`): blob PUT and import multipart carry
    /// megabytes over a mobile uplink, so they legitimately need more room than a
    /// JSON call. One named value, not a number pretending to fit everything.
    public static let upload: TimeInterval = 120

    /// Overall cap for any single resource (session-level `timeoutIntervalForResource`).
    /// Larger than any legitimate request so it never bites first; it exists so a
    /// stuck request cannot run forever.
    public static let resource: TimeInterval = 300

    /// The session configuration the app's one transport builds from. `waitsForConnectivity`
    /// stays at its default (false) so a request times out rather than waiting
    /// silently for a network that may never come.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = readJSON
        configuration.timeoutIntervalForResource = resource
        return configuration
    }
}
