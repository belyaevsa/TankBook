import Foundation

// MARK: - The attempt -> outcome pair around a repository write (OB.2)

/// Runs one repository write wrapped in the `data.mutate.begin` / `ok` / `fail`
/// pair from docs/LOGGING.md §4.
///
/// The caller names the `op` and the `source` because those are caller
/// knowledge, not repository knowledge: a `FillUp` written by the capture
/// door, the typed door, an import or a reminder completion carries a
/// different `source`, and whether an upsert is a create or an update is known
/// only to whoever is doing the saving. A `nil` `log` skips the pair entirely
/// and behaves as a plain `body()` call, so un-wired call sites and the sync
/// merge funnel (which reports through `sync.merge`, one line per batch - not
/// per record, docs/LOGGING.md §7) emit nothing.
///
/// Privacy: this helper accepts only ids, the entity type, the op, the source
/// and field *names* (`fieldsChanged`). The written entity never crosses this
/// boundary, so a fill-up's station, note or amount has no route into the log
/// line even if the caller is careless - the exact property a mutation logger
/// sitting on user content must have (hard rule 12).
///
/// `errorCode` is the stable code recorded on `data.mutate.fail`. The default
/// names the failure class; a caller that can map the thrown error more
/// precisely (a `sqlite_busy`, a GRDB constraint code) passes its own.
public func loggedWrite<T>(_ log: TankbookLog?,
                           op: MutationOp,
                           entityType: String,
                           entityId: UUID,
                           source: MutationSource,
                           errorCode: String = "database.write_failed",
                           fieldsChanged: [String] = [],
                           body: () throws -> T) throws -> T {
    guard let log else { return try body() }
    let mutation = DataMutationLogger(log: log, op: op, entityType: entityType,
                                      entityId: entityId, source: source)
    do {
        let value = try body()
        mutation.ok(fieldsChanged: fieldsChanged)
        return value
    } catch {
        // The write is thrown out of a GRDB transaction, which rolls it back;
        // `rolledBack: true` is therefore the honest report of the pair's fail
        // terminal (docs/LOGGING.md §4). The rendered message is Sensitive and
        // rides `.sensitive`, never `.public`.
        mutation.fail(errorCode: errorCode,
                      errorDomain: String(describing: type(of: error)),
                      underlyingError: error.localizedDescription,
                      rolledBack: true)
        throw error
    }
}

// MARK: - Background task begin/expiry seam (OB.2)

/// Owns the `background.task.begin` / `background.task.expired` pair around a
/// `UIApplication.beginBackgroundTask` guard (docs/LOGGING.md §4, OB.2 async
/// edges). Core owns the event pair so the expiry handler - the iOS async edge
/// no other line can narrate - is testable at L1 with an injected handler; the
/// app target calls `begin` when it starts a backgrounded push/upload and
/// `expired` from the task's `expirationHandler`.
///
/// `kind` is a stable work code (`sync` / `blobUpload`), never an identifier
/// and never a domain value. The granted-time figure is logged only at expiry,
/// where it means "the OS ran out of grace" - a duration, Safe class.
public final class BackgroundTaskLogging: @unchecked Sendable {
    private let log: TankbookLog
    private let kind: String
    private var grantedSeconds: Int = 0

    public init(log: TankbookLog, kind: String) {
        self.log = log
        self.kind = kind
        log.emit(BackgroundTaskBegin(kind: kind))
    }

    /// Records the grace time iOS granted, for the expiry line.
    public func note(grantedSeconds: Int) {
        self.grantedSeconds = grantedSeconds
    }

    /// The `expirationHandler`'s job: iOS is about to suspend the app and the
    /// work had not finished. One line, exactly the edge that is otherwise
    /// invisible.
    public func expired() {
        log.emit(BackgroundTaskExpired(kind: kind, grantedSeconds: grantedSeconds))
    }
}
