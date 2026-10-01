import Foundation

/// PJ.42: the sample receipt - opened, read, finished. Shape only: the stage
/// token and, once read, how many of the three numbers the reader filled.
public struct CaptureDemo: LogEvent {
    public let eventName = "capture.demo"
    public let category = LogCategory.capture
    public let level = LogLevel.info
    public let fields: [LogField]

    /// `stage` is `opened`, `read` or `done`.
    public init(stage: String, fieldsRead: Int? = nil) {
        var fields: [LogField] = [.safe("stage", stage)]
        if let fieldsRead { fields.append(.safe("fieldsRead", fieldsRead)) }
        self.fields = fields
    }
}
