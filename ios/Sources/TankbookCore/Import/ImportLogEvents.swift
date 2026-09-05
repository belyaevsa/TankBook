import Foundation

// The import log event (RV.68, docs/LOGGING.md -> hard rule 12: nothing but
// shape). This row exists because nothing recorded WHICH error an import
// request died on - disproving "you need a connection" needed a server log.
// Only the route path, the error's Swift type name and a URLError code are
// carried; never a payload, never a URL query, never the rendered message (a
// `localizedDescription` can embed paths or domain values and has no route
// into this event).

/// A non-HTTP import failure, logged BEFORE the client maps it to a
/// user-visible error so the mapping is always reconstructible from the log.
/// `endpoint` is the route path (`/v1/import/formats`), `errorType` the Swift
/// type name (`URLError`), and `urlErrorCode` the numeric `URLError.Code` when
/// the error is a `URLError` - all Safe class (docs/LOGGING.md §1).
public struct ImportTransportFailure: LogEvent {
    public let eventName = "import.transport.fail"
    public let category = LogCategory.sync
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(endpoint: String, error: any Error) {
        var fields: [LogField] = [
            .safe("endpoint", endpoint),
            // `URLError` bridges to `NSError` at an `any Error` boundary, so
            // `type(of:)` would report the runtime half; the meaningful name
            // for the diagnostic is the one the classifier reads.
            .safe("errorType", error is URLError ? "URLError" : String(describing: type(of: error)))
        ]
        if let urlError = error as? URLError {
            fields.append(.safe("urlErrorCode", urlError.code.rawValue))
        }
        self.fields = fields
    }
}

/// A local read of a user-picked import file failed (RV.73) - the security-
/// scoped pick could not be copied into the app container, or a staged copy
/// could not be read. Logged at the point of the attempt so the failure is
/// never inferred from the ABSENCE of a server line (the RV.73 diagnosis had
/// to be made that way - `try?` had swallowed the error and no record existed).
///
/// Privacy (docs/LOGGING.md §1, hard rule 12): only the error's Swift type name
/// and its numeric code are carried - both Safe class. **Never the path, never
/// the file name, never a byte of content**: a Cocoa `NSFileReadNoPermissionError`
/// or `NSFileReadNoSuchFileError` names the file it could not open, so the
/// rendered description has no route into this event.
public struct ImportReadFailure: LogEvent {
    public let eventName = "import.read.fail"
    public let category = LogCategory.ui
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(error: any Error) {
        var fields: [LogField] = [
            // `URLError` bridges to `NSError` at an `any Error` boundary, so
            // `type(of:)` would report the runtime half; the meaningful name
            // for the diagnostic is the type the classifier reads.
            .safe("errorType", error is URLError ? "URLError" : String(describing: type(of: error)))
        ]
        if let urlError = error as? URLError {
            fields.append(.safe("errorCode", urlError.code.rawValue))
        } else if let cocoa = error as? CocoaError {
            fields.append(.safe("errorCode", cocoa.errorCode))
        }
        self.fields = fields
    }
}
