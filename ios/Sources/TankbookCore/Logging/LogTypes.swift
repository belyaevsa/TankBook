import Foundation

/// OSLog categories under the `live.belyaev.tankbook` subsystem
/// (docs/LOGGING.md §4). `config` is an iOS-only addition for remote-config
/// events, so the seven categories cover every phase.
public enum LogCategory: String, Sendable, CaseIterable {
    case sync
    case persistence
    case capture
    case notifications
    case ui
    case auth
    case config
}

/// Level discipline per docs/LOGGING.md §3: `error` = failure or integrity risk,
/// `warn` = handled degradation (retry, conflict, quota), `info` = the per-op
/// records, `debug` = development only.
public enum LogLevel: String, Sendable, Equatable {
    case debug
    case info
    case warn
    case error
}

/// The per-line context required on every line by docs/LOGGING.md §2:
/// `deviceId?`, `appVersion`, `platform`. `traceId` is supplied per event by
/// the caller. iOS carries `deviceId` in place of the backend's `accountHash`
/// (no account hash exists on the client).
public struct LogContext: Sendable, Equatable {
    public var deviceId: String?
    public var appVersion: String
    public var platform: String

    public init(deviceId: String? = nil, appVersion: String, platform: String = "ios") {
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.platform = platform
    }

    /// The version of the running bundle; `unknown` when no bundle is present
    /// (unit tests, tooling). The app target overrides this via the Info.plist.
    public static func currentAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
