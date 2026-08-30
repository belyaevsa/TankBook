import Foundation

// The feedback log events (docs/LOGGING.md -> hard rule 12: nothing but shape).
// Only the category, counts, error codes, durations and field *names* are
// logged - never the feedback text, never a replyTo address, never the device
// model string. The payload's domain values have no route into these events.

/// The shape-only fields every feedback event carries. The category is a stable
/// code; `textLength` is a count (never the text); the two `has*` flags record
/// field *presence*, never the values. This is the same discipline as
/// `CapturePipeline`'s field-names-and-confidence.
enum FeedbackShape {
    static func fields(_ payload: FeedbackPayload) -> [LogField] {
        [
            .safe("category", payload.category.rawValue),
            .safe("textLength", payload.text.count),
            .safe("hasReplyTo", payload.replyTo != nil ? "true" : "false"),
            .safe("hasDeviceModel", payload.deviceModel != nil ? "true" : "false")
        ]
    }
}

/// A case was accepted into the queue (consent given). `feedback.queue` is the
/// "intent" half of the attempt -> outcome pair (docs/LOGGING.md §4).
public struct FeedbackQueued: LogEvent {
    public let eventName = "feedback.queue"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(payload: FeedbackPayload) {
        fields = FeedbackShape.fields(payload)
    }
}

/// A case reached the server and was accepted (`202`).
public struct FeedbackSent: LogEvent {
    public let eventName = "feedback.send"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(payload: FeedbackPayload, durationMs: Int) {
        var fields = FeedbackShape.fields(payload)
        fields.append(.safe("durationMs", durationMs))
        self.fields = fields
    }
}

/// A send failed and the case stays queued. `errorCode` is the stable code
/// (`rate_limited`, `transport_unreachable`, `send_failed`); the outcome is a
/// handled degradation, so WARN (docs/LOGGING.md §3).
public struct FeedbackFailed: LogEvent {
    public let eventName = "feedback.fail"
    public let category = LogCategory.ui
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(payload: FeedbackPayload, errorCode: String, durationMs: Int) {
        var fields = FeedbackShape.fields(payload)
        fields.append(.safe("errorCode", errorCode))
        fields.append(.safe("durationMs", durationMs))
        self.fields = fields
    }
}
