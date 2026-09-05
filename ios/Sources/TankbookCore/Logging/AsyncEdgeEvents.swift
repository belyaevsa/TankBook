import Foundation

// MARK: - Async edges and clock evidence (OB.2; docs/LOGGING.md §4)

/// The server clamped one or more pushed `clientUpdatedAt` stamps to its own
/// clock (docs/API.md -> push: stamps >24h in the future are clamped). That is
/// the client-visible evidence that this device's clock runs ahead of the
/// server's, which silently corrupts every LWW decision this device makes, so
/// it is surfaced once per cycle rather than per record.
///
/// Privacy: `clampedCount` is a count and `syncSessionId` an id - both Safe.
/// Which records were clamped is never logged: the id list is the outcome's
/// `clampedIds`, and it stays out of the log line because "this specific entry
/// was clamped" is a domain-meaning signal the log does not need.
public struct SyncClockSkew: LogEvent {
    public let eventName = "sync.clock.skew"
    public let category = LogCategory.sync
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(syncSessionId: UUID, clampedCount: Int) {
        fields = [
            .safe("syncSessionId", syncSessionId.uuidString),
            .safe("clampedCount", clampedCount),
        ]
    }
}

// MARK: - App lifecycle (docs/LOGGING.md §4; OB.2 async edges)

/// The recognised `ScenePhase` vocabulary, mirroring UIKit's with no UIKit
/// import so the event is emittable and testable in core.
public enum AppPhase: String, Sendable, Equatable {
    case active
    case inactive
    case background
}

/// A scene-phase transition (`app.lifecycle`, docs/LOGGING.md §4). Foreground /
/// background transitions are the trigger vocabulary of every automatic sync
/// and rate/catalog refresh, so "did the app come back and what did it run"
/// is observable. `phase` is a stable code - Safe class; there is nothing else
/// on this event because there is nothing else that is loggable here.
public struct AppLifecycle: LogEvent {
    public let eventName = "app.lifecycle"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(phase: AppPhase) {
        fields = [
            .safe("phase", phase.rawValue),
        ]
    }
}

// MARK: - Background task edges (docs/LOGGING.md §4; OB.2 async edges)

/// A `UIApplication.beginBackgroundTask` guard started around a push or upload
/// (OB.2). The `kind` is a stable work code (`sync` / `blobUpload`), never an
/// identifier and never a domain value - Safe class. Nothing else rides begin:
/// the task's granted time and its terminal event are the diagnostic half.
public struct BackgroundTaskBegin: LogEvent {
    public let eventName = "background.task.begin"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(kind: String) {
        fields = [.safe("kind", kind)]
    }
}

/// The background task's expiry handler fired: iOS ran out of grace time and
/// the work had not finished (OB.2). `grantedSeconds` is the time iOS allowed
/// - a duration, Safe class. This is the "the OS killed me mid-write" signal
/// that no other line can produce, which is why the begin/expiry pair exists.
public struct BackgroundTaskExpired: LogEvent {
    public let eventName = "background.task.expired"
    public let category = LogCategory.sync
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(kind: String, grantedSeconds: Int) {
        fields = [
            .safe("kind", kind),
            .safe("grantedSeconds", grantedSeconds),
        ]
    }
}

// MARK: - Network path edges (docs/LOGGING.md §4; OB.2 async edges)

/// A connectivity path change (`network.path`, OB.2). A drop to unsatisfied
/// mid-upload is exactly the class of async edge that is invisible unless it
/// is written when it happens. `from` / `to` are the stable NWPath status
/// codes (`satisfied` / `unsatisfied` / `requiresConnection`) - Safe class,
/// and there is deliberately no interface, no host and no SSID on this event:
/// those are domain/network values that would profile the user's surroundings.
public struct NetworkPathChange: LogEvent {
    public let eventName = "network.path"
    public let category = LogCategory.sync
    public let level: LogLevel
    public let fields: [LogField]

    public init(from: String, to: String) {
        level = (to == "unsatisfied") ? .warn : .info
        fields = [
            .safe("from", from),
            .safe("to", to),
        ]
    }
}
