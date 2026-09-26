import Foundation

/// `capture.pumpRead` (docs/LOGGING.md -> Capture / OCR): how far one pump read
/// got - candidates, drops and their reason codes, verified rows, the fields
/// assigned, the law's refusal code, what it committed. Counts, field names
/// and codes only; a digit has no route into it (hard rule 12).
public struct CapturePumpRead: LogEvent {
    public let eventName = "capture.pumpRead"
    public let category = LogCategory.capture
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(_ summary: PumpReadSummary) {
        var fields: [LogField] = [
            .safe("attempts", summary.attempts),
            .safe("chosen", summary.chosen.map(String.init) ?? "none"),
            .safe("detectedRows", summary.detectedRows),
            .safe("candidates", summary.candidates),
            .safe("kept", summary.kept),
            .safe("verified", summary.verified),
            .safe("roles", summary.roles.isEmpty ? "none" : summary.roles.joined(separator: ",")),
            .safe("committed", summary.committed),
            .safe("budgetHit", summary.budgetHit ? "true" : "false")
        ]
        if let rotation = summary.rotationCW { fields.append(.safe("rotationCW", rotation)) }
        if !summary.dropReasons.isEmpty { fields.append(.safe("dropReasons", summary.dropReasons.joined(separator: ","))) }
        if !summary.skippedReads.isEmpty { fields.append(.safe("skipped", summary.skippedReads.joined(separator: ","))) }
        if let reason = summary.lawReason { fields.append(.safe("lawReason", reason)) }
        self.fields = fields
    }
}
