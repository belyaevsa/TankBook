import Foundation

/// What the live preview told the user before the shutter (PU.40b): the
/// guidance state the detector settled on and how many frames it analysed.
/// Counts and one token only - no pixel, no row and no digit has a route in
/// (hard rule 12). It answers whether the hint fired at all, and at what cost.
public struct CaptureGuidance: LogEvent {
    public let eventName = "capture.guidance"
    public let category = LogCategory.capture
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(state: String, framesAnalysed: Int) {
        fields = [
            .safe("state", state),
            .safe("framesAnalysed", framesAnalysed),
        ]
    }
}
