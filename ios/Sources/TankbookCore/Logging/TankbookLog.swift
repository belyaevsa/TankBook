import Foundation
import os

/// The logging facade. Every line is a typed `LogEvent` whose fields are
/// already classified; the redactor runs before any sink, so a call site cannot
/// emit an unclassified value.
///
/// Each emitted line carries the common fields from docs/LOGGING.md §2:
/// `event`, `traceId?`, `deviceId?`, `appVersion`, `platform`.
public final class TankbookLog: Sendable {
    public let sink: any LogSink
    public let breadcrumbs: Breadcrumbs?
    private let contextProvider: @Sendable () -> LogContext

    public init(sink: any LogSink = OSLogSink(),
                context: @escaping @Sendable () -> LogContext,
                breadcrumbs: Breadcrumbs? = Breadcrumbs()) {
        self.sink = sink
        self.contextProvider = context
        self.breadcrumbs = breadcrumbs
    }

    /// Emits one typed event. `traceId` is the per-request correlation id
    /// (docs/LOGGING.md §2); it lands in the common fields of the line.
    public func emit(_ event: some LogEvent, traceId: UUID? = nil) {
        let context = contextProvider()
        let line = LogLine(
            timestamp: Date(),
            level: event.level,
            category: event.category,
            event: event.eventName,
            traceId: traceId,
            deviceId: context.deviceId,
            appVersion: context.appVersion,
            platform: context.platform,
            fields: Redactor.shared.redact(event.fields)
        )
        sink.emit(line)
        breadcrumbs?.record(line)
    }
}

extension TankbookLog {
    /// A production-configured instance. The app target supplies `deviceId`
    /// (from the Keychain, docs/SECURITY.md) once P1.1 lands.
    public static func makeDefault(sink: any LogSink = OSLogSink(),
                                   deviceId: String? = nil,
                                   breadcrumbs: Breadcrumbs? = Breadcrumbs()) -> TankbookLog {
        TankbookLog(
            sink: sink,
            context: {
                LogContext(deviceId: deviceId, appVersion: LogContext.currentAppVersion(), platform: "ios")
            },
            breadcrumbs: breadcrumbs
        )
    }
}

/// A handle for one create/update/delete/restore that guarantees the
/// attempt -> outcome pair from docs/LOGGING.md §4: `begin` is emitted on
/// construction, and exactly **one** terminal (`ok` or `fail`) is emitted no
/// matter how the call site uses the handle - a second terminal is ignored.
/// A crash between construction and terminal leaves a dangling `begin`, which
/// is itself the diagnostic signal.
public final class DataMutationLogger: @unchecked Sendable {
    private let log: TankbookLog
    private let op: MutationOp
    private let entityType: String
    private let entityId: UUID
    private let source: MutationSource
    private let startedAt: Date
    private let terminalLock = OSAllocatedUnfairLock(initialState: false)

    public init(log: TankbookLog, op: MutationOp, entityType: String, entityId: UUID, source: MutationSource) {
        self.log = log
        self.op = op
        self.entityType = entityType
        self.entityId = entityId
        self.source = source
        self.startedAt = Date()
        log.emit(DataMutationBegin(op: op, entityType: entityType, entityId: entityId, source: source))
    }

    /// Completes the pair with a success. `fieldsChanged` is the list of field
    /// *names* that changed - the API accepts names only, so values cannot leak.
    public func ok(fieldsChanged: [String] = []) {
        guard beginTerminal() else { return }
        log.emit(DataMutationOk(op: op, entityType: entityType, entityId: entityId, source: source,
                                durationMs: elapsedMs(), fieldsChanged: fieldsChanged))
    }

    /// Completes the pair with a failure. `errorCode` is the stable code from
    /// API.md; `rolledBack` records whether the write was rolled back.
    public func fail(errorCode: String, errorDomain: String? = nil,
                     underlyingError: String? = nil, rolledBack: Bool) {
        guard beginTerminal() else { return }
        log.emit(DataMutationFail(op: op, entityType: entityType, entityId: entityId, source: source,
                                  errorCode: errorCode, errorDomain: errorDomain,
                                  underlyingError: underlyingError, rolledBack: rolledBack))
    }

    private func beginTerminal() -> Bool {
        terminalLock.withLock { state in
            if state { return false }
            state = true
            return true
        }
    }

    private func elapsedMs() -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}
