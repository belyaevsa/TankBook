import Foundation

// RV.139 - shape-only observability for the rate pack refresh (docs/LOGGING.md
// §4). Three builds showed auth, sync and config traffic but not one
// `/v1/rates/pack`, and no client line recorded which branch the rate refresh
// took. This event records exactly that: was a pack fetch attempted, did it
// join an in-flight fetch, or did Low Power Mode defer it?

/// One decision inside `RateStore.refresh`. Outcome and trigger only - never a
/// rate, an amount, a date or a currency pair beyond its code (hard rule 12).
/// An `attempted` line that is not followed by the fetch's own `net.request`
/// means the request died before the transport; a session of only `joined`
/// lines means the single-flight slot is not being released.
public struct RatePackRefresh: LogEvent {
    public let eventName = "rates.refresh"
    public let category = LogCategory.config
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(trigger: PowerWorkTrigger, outcome: Outcome) {
        fields = [
            .safe("outcome", outcome.rawValue),
            .safe("trigger", trigger.name),
        ]
    }

    public enum Outcome: String, Sendable {
        /// The refresh claimed the single-flight slot; a fetch is being
        /// attempted and should be followed by its `net.request`/`net.response`.
        case attempted
        /// The refresh joined an in-flight fetch instead of opening a second
        /// request (RV.59); it issues no request of its own.
        case joined
        /// Low Power Mode postponed the refresh (background trigger only). The
        /// deferral registers with the resumer and drains when the mode ends.
        case deferred
    }
}
