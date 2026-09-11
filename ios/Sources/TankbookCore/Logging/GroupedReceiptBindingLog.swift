import Foundation

// MARK: - The grouped save's dropped attachment binding (RV.173, docs/LOGGING.md §4)

/// The shape-only record that a grouped save wrote its accepted expenses with
/// NO attachment because the one shared receipt-photo write failed. It answers
/// the question the RV.149 `app.error` line cannot - did a GROUPED save drop
/// the binding? - with a count, never a filename, an amount or a station (hard
/// rule 12). Emitted once per degraded group, beside the single user report,
/// never once per row.
///
/// It lives beside `CaptureCommitLog` rather than in `LogEvents.swift`, which is
/// already over its file-length limit.
public struct GroupedSaveReceiptLost: LogEvent {
    public let eventName = "receipt.group.photoLost"
    public let category = LogCategory.capture
    public let level = LogLevel.warn
    public let fields: [LogField]

    /// `expenseCount` is how many accepted `Expense` rows were written without
    /// the attachment - a count, the whole shape of the event.
    public init(expenseCount: Int) {
        fields = [.safe("expenseCount", expenseCount)]
    }
}
