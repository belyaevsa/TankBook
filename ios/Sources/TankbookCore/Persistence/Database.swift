import Foundation
import GRDB

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
        try writer.write(block)
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
