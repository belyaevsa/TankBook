import Foundation

// RV.152 - shape-only observability for a "Convert the log" answer (docs/
// LOGGING.md §4). A convert that only partially succeeds looks complete on
// screen - every figure populated, nothing pending - so one device log line
// must answer "how many converted, how many went pending?" without an amount,
// a currency pair's values, a station or a date (hard rule 12).

/// One line per home-currency "Convert the log" answer. Counts only: the
/// entries whose derived home figure was restated, and the entries whose date
/// had no rate and so stayed rate-pending (the ordinary F9 state). Never a
/// rate, an amount, a station or a date - the fields are exactly the two
/// counts hard rule 12 permits.
public struct HomeCurrencyConverted: LogEvent {
    public let eventName = "currency.convert"
    public let category = LogCategory.persistence
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(converted: Int, pending: Int) {
        fields = [
            .safe("converted", converted),
            .safe("pending", pending)
        ]
    }
}
