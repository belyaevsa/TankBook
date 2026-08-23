import Foundation
import TankbookCore

/// Owns the app target's SQLite connection. Lazy, so the first screen that
/// needs persistence opens the database without a global init; the connection
/// lives for the process (docs/SYNC.md: local-first, the on-device database is
/// authoritative). MainActor-isolated: every caller today is a SwiftUI view.
@MainActor
enum AppStore {
    private static var cached: TankbookRepository?

    static func repository() throws -> TankbookRepository {
        if let cached { return cached }
        let repository = try makeRepository()
        cached = repository
        return repository
    }

    private static func makeRepository() throws -> TankbookRepository {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try TankbookDatabase(
            path: directory.appendingPathComponent("tankbook.sqlite").path)
        return TankbookRepository(database: database)
    }
}
