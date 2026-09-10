import Foundation

// RV.192 - shape-only observability for the same-day pace rule (docs/LOGGING.md
// §4). A same-day neighbour contributes no pace bound (docs/SCHEMA.md,
// Validation), so a pace flag that used to fire can stop firing with nothing on
// screen to distinguish "the rule suppressed it" from "there was never a
// conflict". One device log line answers that, with counts only.

/// One line per re-validation that skipped at least one pace comparison because
/// a pair shared a calendar day. Fields are the vehicle id and the number of
/// comparisons skipped - ids and counts, which hard rule 12 permits. Never an
/// odometer, a date or a pace.
public struct TimelinePaceSuppressed: LogEvent {
    public let eventName = "timeline.pace.suppressed"
    public let category = LogCategory.persistence
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(vehicleId: UUID, suppressed: Int) {
        fields = [
            .safe("vehicleId", vehicleId.uuidString),
            .safe("suppressed", suppressed)
        ]
    }
}
