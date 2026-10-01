import Foundation

/// PJ.16: a capture-readiness moment - a hint shown, the torch toggled, an
/// auto-shutter fired. Shape only: the hint/action token, never a frame
/// (hard rule 12).
public struct CaptureReadiness: LogEvent {
    public let eventName = "capture.readiness"
    public let category = LogCategory.capture
    public let level = LogLevel.info
    public let fields: [LogField]

    /// `action` is one of `hint.dark`, `hint.fillFrame`, `torch.on`, `torch.off`, `autoShutter`.
    public init(action: String) {
        fields = [.safe("action", action)]
    }
}
