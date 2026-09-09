import Foundation
import GRDB
import os

/// A fire-and-forget "a write committed" signal the app can observe
/// (docs/SYNC.md, the debounced write trigger). The repository itself knows
/// nothing about sync - it only announces that a local write happened; the app
/// decides whether that means a sync cycle should run. The signal is a single
/// shared box per database, so every `TankbookRepository` copy (and the app's
/// cached instance) observes the same writes. Thread-safe: writes commit on
/// whichever thread called them.
public final class DatabaseWriteSignal: @unchecked Sendable {
    private struct State {
        var observer: (@Sendable () -> Void)?
        /// Nestable suppression: while > 0 the signal stays silent. The sync
        /// engine raises it for the duration of a cycle so its OWN writes (the
        /// bookkeeping that is the response to a sync) never announce as a new
        /// local write - without this, an offline push that leaves rows dirty
        /// would re-trigger the debounced write-trigger forever.
        var suppression = 0
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    /// The observer the app registers once. nil = nobody is listening (tests,
    /// un-wired embeddings), and `fire()` is then a no-op.
    public var observer: (@Sendable () -> Void)? {
        get { lock.withLock { $0.observer } }
        set { lock.withLock { $0.observer = newValue } }
    }

    /// Silences announcements until the matching `resume` runs. Nestable and
    /// thread-safe (the engine brackets a whole asynchronous cycle with it).
    public func suppress() {
        lock.withLock { $0.suppression += 1 }
    }

    /// Re-arms announcements after `suppress`. Safe to over-call (clamped at 0).
    public func resume() {
        lock.withLock { $0.suppression = max(0, $0.suppression - 1) }
    }

    /// Invokes the observer, if any and not suppressed. Called after every
    /// successful write transaction; never from within the transaction.
    public func fire() {
        let observer = lock.withLock { state -> (@Sendable () -> Void)? in
            guard state.suppression == 0 else { return nil }
            return state.observer
        }
        observer?()
    }
}

/// Owns the SQLite connection and applies the migrations on open.
///
/// - On-disk databases open in WAL mode so readers and the writer don't block
///   each other (GRDB observation + SwiftUI reads on one thread while the
///   sync queue writes on another).
/// - Foreign keys are always enabled; the schema's `vehicleId` references rely
///   on it (docs/SCHEMA.md, soft-delete principle: hard purges cascade, soft
///   deletes tombstone).
public struct TankbookDatabase {
    public let writer: any DatabaseWriter
    public let migrator: DatabaseMigrator
    /// Fired after every successful write transaction (the app's debounced
    /// write-trigger seam). A reference type stored on the struct, so all
    /// copies of one database share the same signal.
    public let writeSignal = DatabaseWriteSignal()

    /// Opens (creating if needed) the database at `path` and migrates it.
    public init(path: String, migrator: DatabaseMigrator = TankbookMigrations.migrator) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        let writer = try DatabaseQueue(path: path, configuration: configuration)
        try migrator.migrate(writer)
        self.writer = writer
        self.migrator = migrator
    }

    /// Opens an independent in-memory database for tests and migrated it the
    /// same way. WAL is meaningless for in-memory databases (SQLite reports
    /// `memory`), so the default journal mode is left in place.
    public static func inMemory(migrator: DatabaseMigrator = TankbookMigrations.migrator) throws -> TankbookDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let writer = try DatabaseQueue(configuration: configuration)
        try migrator.migrate(writer)
        return TankbookDatabase(writer: writer, migrator: migrator)
    }

    /// Opens an in-memory database migrated only up to `version` (GRDB's
    /// `migrate(_:upTo:)`). Test support: seed a schema at an older version and
    /// then apply the forward migrations over the seeded rows, proving each
    /// migration is additive rather than a rewrite.
    public static func inMemory(upTo version: String,
                                migrator: DatabaseMigrator = TankbookMigrations.migrator) throws -> TankbookDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let writer = try DatabaseQueue(configuration: configuration)
        try migrator.migrate(writer, upTo: version)
        return TankbookDatabase(writer: writer, migrator: migrator)
    }

    private init(writer: any DatabaseWriter, migrator: DatabaseMigrator) {
        self.writer = writer
        self.migrator = migrator
    }

    /// Runs a read access (a snapshot on the writer).
    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        try writer.read(block)
    }

    /// Runs a write access in a transaction.
    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        let result = try writer.write(block)
        writeSignal.fire()
        return result
    }

    /// Names of all tables, queried from `sqlite_master`. Exposed so tests and
    /// diagnostics can verify the migrated schema without importing GRDB.
    public func tableNames() throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
    }

    /// Names of all explicit indexes (auto-indexes have a NULL `sql` and are
    /// excluded), queried from `sqlite_master`.
    public func indexNames() throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL ORDER BY name")
        }
    }
}
