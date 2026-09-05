import Foundation

/// A typed, documented log event. Field lists are fixed per event so a call
/// site cannot invent an ad-hoc message; every field is already classified
/// (docs/LOGGING.md §1, §4).
public protocol LogEvent: Sendable {
    /// The stable event name, e.g. `data.mutate.begin`.
    var eventName: String { get }
    var category: LogCategory { get }
    var level: LogLevel { get }
    var fields: [LogField] { get }
}

// MARK: - Shared vocabulary (docs/LOGGING.md §4, docs/SCHEMA.md names)

public enum MutationOp: String, Sendable {
    case create
    case update
    case delete
    case restore
}

public enum MutationSource: String, Sendable {
    case capture
    case manual
    case `import`
    case syncMerge
    case reminder
}

public enum ValidationResult: String, Sendable {
    case ok
    case flagged
}

// MARK: - Local mutations: the attempt -> outcome pair (docs/LOGGING.md §4)

/// Intent: the write is about to start. A crash between `begin` and its
/// terminal outcome is itself diagnostic, which is why the pair exists.
public struct DataMutationBegin: LogEvent {
    public let eventName = "data.mutate.begin"
    public let category = LogCategory.persistence
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(op: MutationOp, entityType: String, entityId: UUID, source: MutationSource) {
        fields = [
            .safe("op", op.rawValue),
            .safe("entityType", entityType),
            .safe("entityId", entityId.uuidString),
            .safe("source", source.rawValue),
        ]
    }
}

/// Success outcome. `fieldsChanged` carries field *names* only - never values.
public struct DataMutationOk: LogEvent {
    public let eventName = "data.mutate.ok"
    public let category = LogCategory.persistence
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(op: MutationOp, entityType: String, entityId: UUID, source: MutationSource,
                durationMs: Int, fieldsChanged: [String]) {
        fields = [
            .safe("op", op.rawValue),
            .safe("entityType", entityType),
            .safe("entityId", entityId.uuidString),
            .safe("source", source.rawValue),
            .safe("durationMs", durationMs),
            .safe("fieldsChanged", fieldsChanged.joined(separator: ",")),
        ]
    }
}

/// Failure outcome. `errorCode` is the stable code from API.md; `underlyingError`
/// is downgraded to sensitive because an error description may embed paths or
/// domain values (docs/LOGGING.md §1: when in doubt, downgrade).
public struct DataMutationFail: LogEvent {
    public let eventName = "data.mutate.fail"
    public let category = LogCategory.persistence
    public let level = LogLevel.error
    public let fields: [LogField]

    public init(op: MutationOp, entityType: String, entityId: UUID, source: MutationSource,
                errorCode: String, errorDomain: String? = nil,
                underlyingError: String? = nil, rolledBack: Bool) {
        var fields: [LogField] = [
            .safe("op", op.rawValue),
            .safe("entityType", entityType),
            .safe("entityId", entityId.uuidString),
            .safe("source", source.rawValue),
            .safe("errorCode", errorCode),
            .safe("rolledBack", rolledBack ? "true" : "false"),
        ]
        if let errorDomain {
            fields.append(.safe("errorDomain", errorDomain))
        }
        if let underlyingError {
            fields.append(.sensitive("underlyingError", underlyingError))
        }
        self.fields = fields
    }
}

/// Timeline validation after a merge or edit (docs/LOGGING.md §4).
public struct DataValidate: LogEvent {
    public let eventName = "data.validate"
    public let category = LogCategory.persistence
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(entityId: UUID, result: ValidationResult,
                conflictKind: ConflictState.ConflictKind? = nil,
                crossCheck: CrossCheckState? = nil) {
        var fields: [LogField] = [
            .safe("entityId", entityId.uuidString),
            .safe("result", result.rawValue),
        ]
        if let kind = conflictKind {
            fields.append(.safe("conflictKind", kind.rawValue))
        }
        if let crossCheck {
            fields.append(.safe("crossCheck", Self.describe(crossCheck)))
        }
        self.fields = fields
    }

    private static func describe(_ state: CrossCheckState) -> String {
        switch state {
        case .verified: return "verified"
        case .notApplicable: return "notApplicable"
        case .mismatch(let field): return "mismatch:\(field.stringValue)"
        }
    }
}

/// Full-vehicle recompute - catches the "stats look wrong" class of bug
/// (docs/LOGGING.md §4, hard rule 2: stats are derived, never stored).
public struct DataRecompute: LogEvent {
    public let eventName = "data.recompute"
    public let category = LogCategory.persistence
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(vehicleId: UUID, segmentsBefore: Int, segmentsAfter: Int, durationMs: Int) {
        fields = [
            .safe("vehicleId", vehicleId.uuidString),
            .safe("segmentsBefore", segmentsBefore),
            .safe("segmentsAfter", segmentsAfter),
            .safe("durationMs", durationMs),
        ]
    }
}

// MARK: - Requests and their results (docs/LOGGING.md §4)

/// Outgoing request. `endpoint` is the route path (e.g. `/v1/sync/pull`), not
/// a raw URL with its query string - ids and query values stay out of paths in
/// logs (docs/LOGGING.md §3), and `requestBytes` is the body's byte count,
/// never the body. The request's `traceId` rides the common line via the
/// facade's `traceId:` argument, which is the per-request correlation id from
/// docs/LOGGING.md §2.
///
/// Privacy: `endpoint` is a route path (Safe), `method` a verb (Safe), `attempt`
/// a count (Safe), `requestBytes` a byte count (Safe). No header, no query,
/// no body value and no token ever reach this event - the fields are exactly
/// the four hard rule 12 permits, so a future contributor adding e.g. a host
/// or a body preview would break the class contract at the call site and in the
/// privacy sweep.
public struct NetRequest: LogEvent {
    public let eventName = "net.request"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(endpoint: String, method: String, attempt: Int, requestBytes: Int) {
        fields = [
            .safe("endpoint", endpoint),
            .safe("method", method),
            .safe("attempt", attempt),
            .safe("requestBytes", requestBytes),
        ]
    }
}

/// Response / result of a request, including the retry/backoff decision so a
/// "sync seems stuck" report is explicable. Failure-level responses log at
/// `warn` (handled degradation - docs/LOGGING.md §3).
///
/// Privacy: this is where a doubled upload (RV.65) or a duplicate fetch
/// (RV.59) shows up from the device side, which is why `requestBytes` and
/// `responseBytes` ride here - byte counts, never bodies. Every field is Safe
/// class: `endpoint` is the route path, `status`/`durationMs`/the byte counts
/// are numbers, `retryAfter` is seconds, `errorCode` is a stable code.
/// Nothing that a body could contain - no values, no tokens, no host - has an
/// API onto this event.
public struct NetResponse: LogEvent {
    public let eventName = "net.response"
    public let category = LogCategory.sync
    public let level: LogLevel
    public let fields: [LogField]

    public init(endpoint: String, status: Int, durationMs: Int,
                requestBytes: Int = 0, responseBytes: Int = 0,
                retryAfter: Int? = nil, errorCode: String? = nil,
                willRetry: Bool = false) {
        level = (status >= 400 || errorCode != nil) ? .warn : .info
        var fields: [LogField] = [
            .safe("endpoint", endpoint),
            .safe("status", status),
            .safe("durationMs", durationMs),
            .safe("requestBytes", requestBytes),
            .safe("responseBytes", responseBytes),
            .safe("willRetry", willRetry ? "true" : "false"),
        ]
        if let retryAfter {
            fields.append(.safe("retryAfter", retryAfter))
        }
        if let errorCode {
            fields.append(.safe("errorCode", errorCode))
        }
        self.fields = fields
    }
}

// MARK: - Sync client (docs/LOGGING.md §4, docs/SYNC.md S1-S8)

public enum SyncTrigger: String, Sendable {
    // The two doors the client actually distinguishes today (docs/SYNC.md):
    // app-scheduled work (launch, foreground, timer, debounced write, a WiFi
    // change) all arrives as `.background`; a sync the user asked for is
    // `.userInitiated`. The doc vocabulary below (foreground/write/nudge) names
    // the individual automatic doors, which the app cannot tell apart yet - so
    // `background` is the honest carrier until they are wired individually.
    case background
    case userInitiated
    // The docs' semantic doors (docs/LOGGING.md §4). Present in the enum for
    // callers that DO know which automatic door fired; today the engine maps
    // every `.background` PowerWorkTrigger onto `.background` because the
    // distinguishing signal does not exist on the wire yet.
    case foreground
    case write
    case nudge
}

extension PowerWorkTrigger {
    /// The cycle-event trigger vocabulary for this work trigger. The engine
    /// only ever hears `background` / `userInitiated` (the two doors above);
    /// the finer automatic doors are future refinements, never guessed here.
    var syncTrigger: SyncTrigger {
        switch self {
        case .background: return .background
        case .userInitiated: return .userInitiated
        }
    }
}

public enum SyncScenario: String, Sendable, CaseIterable {
    case s1 = "S1"
    case s2 = "S2"
    case s3 = "S3"
    case s4 = "S4"
    case s5 = "S5"
    case s6 = "S6"
    case s7 = "S7"
    case s8 = "S8"
}

/// A conflict tally for one SYNC.md scenario. Aggregated - never one entry per
/// record, which is what keeps a merge O(1) lines (docs/LOGGING.md §7, level
/// discipline test).
public struct SyncConflict: Sendable, Equatable {
    public let scenario: SyncScenario
    public let count: Int

    public init(scenario: SyncScenario, count: Int) {
        self.scenario = scenario
        self.count = count
    }
}

public struct SyncCycleBegin: LogEvent {
    public let eventName = "sync.cycle.begin"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(syncSessionId: UUID, trigger: SyncTrigger) {
        fields = [
            .safe("syncSessionId", syncSessionId.uuidString),
            .safe("trigger", trigger.rawValue),
        ]
    }
}

public struct SyncCycleEnd: LogEvent {
    public let eventName = "sync.cycle.end"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(syncSessionId: UUID, durationMs: Int,
                recordsPulled: Int? = nil, recordsPushed: Int? = nil) {
        var fields: [LogField] = [
            .safe("syncSessionId", syncSessionId.uuidString),
            .safe("durationMs", durationMs),
        ]
        if let recordsPulled {
            fields.append(.safe("recordsPulled", recordsPulled))
        }
        if let recordsPushed {
            fields.append(.safe("recordsPushed", recordsPushed))
        }
        self.fields = fields
    }
}

/// RV.18: a sync cycle actually fired. Emitted once per non-inert cycle with
/// the trigger that asked and the running per-trigger totals, so "how often
/// sync fires, and by which door" is observable in the field. Counts and a
/// trigger name only - hard rule 12, never a domain value.
public struct SyncCycleFired: LogEvent {
    public let eventName = "sync.cycle.fired"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(trigger: String, backgroundCount: Int, userInitiatedCount: Int) {
        fields = [
            .safe("trigger", trigger),
            .safe("backgroundCount", backgroundCount),
            .safe("userInitiatedCount", userInitiatedCount),
        ]
    }
}

public struct SyncMerge: LogEvent {
    public let eventName = "sync.merge"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    /// `recordsApplied` is a count, not a list - the merge of N records is one
    /// line (docs/LOGGING.md §7 volume discipline). Conflicts are aggregated by
    /// SYNC.md scenario so conflict behaviour is observable in the field.
    public init(recordsApplied: Int, conflicts: [SyncConflict], durationMs: Int? = nil) {
        var fields: [LogField] = [
            .safe("recordsApplied", recordsApplied),
        ]
        if !conflicts.isEmpty {
            let tally = conflicts
                .map { "\($0.scenario.rawValue):\($0.count)" }
                .joined(separator: ",")
            fields.append(.safe("conflict", tally))
        }
        if let durationMs {
            fields.append(.safe("durationMs", durationMs))
        }
        self.fields = fields
    }
}

public struct SyncQueue: LogEvent {
    public let eventName = "sync.queue"
    public let category = LogCategory.sync
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(dirtyCount: Int, oldestDirtyAgeSeconds: Int) {
        fields = [
            .safe("dirtyCount", dirtyCount),
            .safe("oldestDirtyAgeSeconds", oldestDirtyAgeSeconds),
        ]
    }
}

// MARK: - Remote config (docs/LOGGING.md §4, docs/CONFIG.md -> "Logging")

/// A config layer was applied. Config is our data, not the user's, so every
/// field here is Safe class. `changedKeys` carries field *names* only - never
/// the values (docs/LOGGING.md hard rule 12), and never the document body.
public struct ConfigApply: LogEvent {
    public let eventName = "config.apply"
    public let category = LogCategory.config
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(version: Int, source: ConfigSource, changedKeys: [String]) {
        let keys = changedKeys.isEmpty ? "" : changedKeys.sorted().joined(separator: ",")
        fields = [
            .safe("version", version),
            .safe("source", source.rawValue),
            .safe("changedKeys", keys),
        ]
    }
}

/// A config document was rejected whole (docs/CONFIG.md -> "Document level: all
/// or nothing"). `reason` is a stable code, not a domain value.
public struct ConfigReject: LogEvent {
    public let eventName = "config.reject"
    public let category = LogCategory.config
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(reason: ConfigRejectReason) {
        fields = [.safe("reason", reason.rawValue)]
    }
}

/// A candidate `apiBaseUrl` passed its health gate and was promoted to active
/// (docs/CONFIG.md -> "Health gate before adoption"). The host is our data, not
/// the user's, so it is Safe class; only the host is logged, never a token and
/// never the full document (docs/LOGGING.md hard rule 12).
public struct ConfigBaseURLPromote: LogEvent {
    public let eventName = "config.baseurl.promote"
    public let category = LogCategory.config
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(host: String) {
        fields = [.safe("host", host)]
    }
}

/// The active `apiBaseUrl` produced N consecutive transport failures and the
/// client reverted to the bundled default (docs/CONFIG.md -> "Auto-revert on
/// sustained failure"). Logged at WARN with the failure count and the host that
/// was abandoned - host and counts are Safe class, a token never is.
public struct ConfigBaseURLRevert: LogEvent {
    public let eventName = "config.baseurl.revert"
    public let category = LogCategory.config
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(host: String, failureCount: Int) {
        fields = [
            .safe("host", host),
            .safe("failureCount", failureCount),
        ]
    }
}

// MARK: - Vehicle catalog updates (docs/SYNC.md -> Reference data)

/// Which catalog layer is now serving. The catalog is our data, not the user's,
/// so these are Safe-class fields.
public enum CatalogPackSource: String, Sendable {
    case bundled
    case cache
    case live
}

/// A catalog layer was applied (docs/SYNC.md -> "Applying an update"). Only
/// versions, sources and counts are logged - never the pack body and never a
/// model name (docs/LOGGING.md hard rule 12).
public struct CatalogApply: LogEvent {
    public let eventName = "catalog.apply"
    public let category = LogCategory.config
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(version: Int, source: CatalogPackSource, changedEntries: Int) {
        fields = [
            .safe("version", version),
            .safe("source", source.rawValue),
            .safe("changedEntries", changedEntries),
        ]
    }
}

/// A catalog pack was not applied (docs/ERRORS.md -> Vehicle catalog updates:
/// every failure here is invisible). `reason` is a stable code. Logged at WARN
/// - handled degradation - and the previous layer keeps serving.
public struct CatalogReject: LogEvent {
    public let eventName = "catalog.reject"
    public let category = LogCategory.config
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(reason: CatalogRejectReason) {
        fields = [.safe("reason", reason.rawValue)]
    }
}

/// One "model not found" search miss (docs/SYNC.md -> Curation feedback loop).
/// Only the running count is logged; the typed text is Never-class and can
/// never be attached (docs/LOGGING.md hard rule 12).
public struct CatalogMiss: LogEvent {
    public let eventName = "catalog.miss"
    public let category = LogCategory.config
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(totalCount: Int) {
        fields = [.safe("totalCount", totalCount)]
    }
}

// MARK: - Capture / OCR (docs/LOGGING.md §4)

/// One OCR field: the field *name* and its confidence value, never the
/// extracted value.
public struct CapturedField: Sendable, Equatable {
    public let name: FieldRef
    public let confidence: Double

    public init(name: FieldRef, confidence: Double) {
        self.name = name
        self.confidence = confidence
    }
}

public struct CapturePipeline: LogEvent {
    public let eventName = "capture.pipeline"
    public let category = LogCategory.capture
    public let level = LogLevel.info
    public let fields: [LogField]

    /// `fields` carries per-field names + confidence only; extracted values are
    /// Never-class and can never be attached here (aggregate-safe by
    /// construction - docs/LOGGING.md §4).
    public init(pipelineId: String, durationMs: Int, fields: [CapturedField],
                crossCheck: CrossCheckState? = nil, userCorrected: Bool = false) {
        var logFields: [LogField] = [
            .safe("pipelineId", pipelineId),
            .safe("durationMs", durationMs),
        ]
        for field in fields {
            logFields.append(.safe("field", "\(field.name.stringValue):\(Self.confidence(field.confidence))"))
        }
        if let crossCheck {
            logFields.append(.safe("crossCheck", Self.describe(crossCheck)))
        }
        logFields.append(.safe("userCorrected", userCorrected ? "true" : "false"))
        self.fields = logFields
    }

    private static func describe(_ state: CrossCheckState) -> String {
        switch state {
        case .verified: return "verified"
        case .notApplicable: return "notApplicable"
        case .mismatch(let field): return "mismatch:\(field.stringValue)"
        }
    }

    private static func confidence(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
    }
}

// MARK: - Fiscal QR (docs/LOGGING.md §4, docs/TASKS.md P2.6)

/// The outcome of parsing a fiscal QR payload.
public enum FiscalQRParseOutcome: String, Sendable {
    case parsed
    case rejected
}

/// One fiscal-QR parse, emitted by the parser half (docs/TASKS.md P2.6).
///
/// Hard rule 12 is absolute here: only the outcome and - on failure - a stable
/// `reason` code that may carry field *names* are logged. The total, the
/// timestamp and any of `fn`/`i`/`fp` are the user's purchase and are never
/// attached at any level.
public struct FiscalQRParse: LogEvent {
    public let eventName = "fiscal.qr.parse"
    public let category = LogCategory.capture
    public let level: LogLevel
    public let fields: [LogField]

    /// `reason` is a stable code from `FiscalQRParseError.reasonCode`, e.g.
    /// `missingField:total` - a field name, never a value.
    public init(outcome: FiscalQRParseOutcome, reason: String? = nil) {
        level = (outcome == .parsed) ? .info : .warn
        var fields: [LogField] = [.safe("outcome", outcome.rawValue)]
        if let reason {
            fields.append(.safe("reason", reason))
        }
        self.fields = fields
    }
}

// MARK: - App-layer errors (docs/LOGGING.md §4 Errors)

/// An app-layer failure (docs/LOGGING.md §4 Errors). `operation` is a stable
/// code naming the action in flight (e.g. `home.load`) and `errorType` is the
/// error's Swift type name - both Safe. The rendered `localizedDescription` is
/// Sensitive: a GRDB error can embed its statement's arguments (station names,
/// notes, amounts), so it is never `.public` (hard rule 12). What stays
/// loggable is what hard rule 12 already permits - the type and a stable code,
/// never the rendered message.
public struct AppError: LogEvent {
    public let eventName = "app.error"
    public let category: LogCategory
    public let level = LogLevel.error
    public let fields: [LogField]

    public init(operation: String, category: LogCategory, error: any Error) {
        self.category = category
        fields = [
            .safe("operation", operation),
            .safe("errorType", String(describing: type(of: error))),
            .sensitive("errorDescription", error.localizedDescription)
        ]
    }
}

/// A handled degradation at the app layer (docs/LOGGING.md §3: WARN, never
/// ERROR). `reason` is a stable code, never a domain value and never a rendered
/// message (hard rule 12).
public struct AppWarning: LogEvent {
    public let eventName = "app.warning"
    public let category: LogCategory
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(operation: String, category: LogCategory, reason: String) {
        self.category = category
        fields = [
            .safe("operation", operation),
            .safe("reason", reason)
        ]
    }
}
