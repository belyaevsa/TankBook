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

    /// True once the `-homeResetDatabase` wipe has run this process. Five seeds
    /// (Home, Recently deleted, Tank level, Tire sets, Reminders) all reset on
    /// that argument; each used to carry its own private flag, so a launch with
    /// several `-seed*` arguments reset the database more than once and the
    /// second reset wiped the first seed's data (P3.8). One gate on AppStore
    /// makes the wipe run at most once per launch, no matter how many seeds see
    /// the argument.
    private static var didResetForLaunch = false

    /// Wipes the on-device database so a UI test run can start each state from
    /// a clean slate, at most once per process. Test-only: called from the
    /// seeding hooks under `-homeResetDatabase` (see HomeTestSeed). The cached
    /// repository must be dropped first or GRDB would keep pointing at a
    /// deleted file.
    static func resetForTestsOncePerLaunch() {
        guard !Self.didResetForLaunch else { return }
        Self.didResetForLaunch = true
        try? resetForTests()
    }

    private static func resetForTests() throws {
        cached = nil
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
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
