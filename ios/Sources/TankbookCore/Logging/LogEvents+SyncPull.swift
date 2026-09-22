import Foundation

// The pull-side sync events (docs/LOGGING.md -> Sync client).

/// One pulled record whose parent row exists nowhere in the account. Ids and
/// entity types only (hard rule 12).
public struct SyncOrphanedRecord: Sendable, Equatable {
    public let entityType: String
    public let id: UUID

    public init(entityType: String, id: UUID) {
        self.entityType = entityType
        self.id = id
    }
}

/// One `sync.orphaned` line per pull that ends with records it could not apply
/// because the row they reference is on no page of the account. The records
/// stay on the server and are not on this device; the cursor moves past them
/// so the account keeps syncing.
public struct SyncOrphanedRecords: LogEvent {
    public let eventName = "sync.orphaned"
    public let category = LogCategory.sync
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(items: [SyncOrphanedRecord]) {
        fields = [
            .safe("count", items.count),
            .safe("items", items.map { "\($0.entityType):\($0.id.uuidString)" }.joined(separator: ",")),
        ]
    }
}

/// The pull half of a cycle threw and the cycle stopped. `error` is the
/// failure's type name (plus SQLite's result code for a database failure) -
/// never its description, which for a database error can quote statement
/// arguments (hard rule 12).
public struct SyncPullFailed: LogEvent {
    public let eventName = "sync.pull.failed"
    public let category = LogCategory.sync
    public let level = LogLevel.warn
    public let fields: [LogField]

    public init(error: any Error) {
        fields = [.safe("error", Self.classify(error))]
    }

    static func classify(_ error: any Error) -> String {
        if let code = TankbookRepository.databaseResultCode(error) { return "DatabaseError:\(code)" }
        // A SyncServerError's description is its case and its status/wait numbers.
        if let server = error as? SyncServerError { return "SyncServerError.\(server)" }
        return String(describing: type(of: error))
    }
}
