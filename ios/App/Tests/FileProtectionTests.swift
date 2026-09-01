import XCTest
@testable import Tankbook

/// PR.16: docs/SECURITY.md promises `completeUntilFirstUserAuthentication` on
/// the database triple and on attachment files, and nothing set it - the class
/// rode the platform default. These are executed assertions against real files
/// on disk in the app's own container (L2), so they must live in the app-target
/// test bundle: the SwiftPM core tests run on macOS, where the app's
/// Application Support path does not exist and the protection attribute does
/// nothing. The `-wal` and `-shm` files carry the most recent rows; asserting
/// only `.sqlite` would prove nothing about them.
///
/// The two tests below that read `resourceValues(forKeys: [.fileProtectionKey])`
/// are the **device-truth** half: they are worthless on the iOS Simulator - it
/// does not emulate data protection and reports the class as a hard constant no
/// matter what is set - but they are correct on a real device, so they stay.
/// The seam-based tests (`*Seam*`) are the discriminating half (PR.16b): they
/// swap `FileProtection.applier` for a recorder and assert the promised class
/// was applied per file, which fails on a simulator too.
@MainActor
final class FileProtectionTests: XCTestCase {

    // MARK: - Device truth (correct on hardware, constant on the simulator)

    func testDatabaseTripleCarriesCompleteUntilFirstUserAuthentication() throws {
        _ = try AppStore.repository()
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("tankbook.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try assertCompleteProtection(URL(fileURLWithPath: databaseURL.path + suffix))
        }
    }

    func testWrittenAttachmentCarriesCompleteUntilFirstUserAuthentication() throws {
        let id = UUID()
        let (_, relativePath) = try VehiclePhotoStore.save(Data("PR.16 test attachment".utf8), id: id)
        let url = try VehiclePhotoStore.attachmentsDirectory().appendingPathComponent(relativePath)
        defer { try? FileManager.default.removeItem(at: url) }
        try assertCompleteProtection(url)
    }

    private func assertCompleteProtection(_ url: URL,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) throws {
        let values = try url.resourceValues(forKeys: [.fileProtectionKey])
        let actual = values.fileProtection
        let message = "\(url.lastPathComponent): file protection = \(actual?.rawValue ?? "nil")"
        XCTAssertEqual(actual, .completeUntilFirstUserAuthentication, message, file: file, line: line)
    }

    // MARK: - Seam (discriminating on a simulator, PR.16b)

    /// The database triple: `makeRepository` must apply the promised class to
    /// `.sqlite`, `-wal` and `-shm` through the shared seam. This is the trap
    /// the row exists for - asserting only `AppStore` (or only `.sqlite`) would
    /// prove nothing about the WAL and SHM files people forget.
    func testDatabaseTripleSeamAppliesPromisedClassPerFile() throws {
        AppStore.dropCachedRepositoryForTests()
        let recorder = ProtectionRecorder()
        let original = AppStore.fileProtectionApplier
        AppStore.fileProtectionApplier = { protectionClass, url in
            recorder.record(protectionClass.rawValue, url: url)
        }
        defer { AppStore.fileProtectionApplier = original }

        _ = try AppStore.repository()

        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("tankbook.sqlite")
        let recorded = recorder.snapshot()
        for suffix in ["", "-wal", "-shm"] {
            assertPromisedClassApplied(
                to: URL(fileURLWithPath: databaseURL.path + suffix), recorded: recorded)
        }
    }

    /// The attachments directory chokepoint: `save` must apply the promised
    /// class to the directory every attachment is written into. The directory
    /// is half the promise - the database triple is the other half.
    func testAttachmentDirectorySeamAppliesPromisedClass() throws {
        let recorder = ProtectionRecorder()
        let original = AppStore.fileProtectionApplier
        AppStore.fileProtectionApplier = { protectionClass, url in
            recorder.record(protectionClass.rawValue, url: url)
        }
        defer { AppStore.fileProtectionApplier = original }

        let id = UUID()
        let (_, relativePath) = try VehiclePhotoStore.save(Data("PR.16b attachment".utf8), id: id)
        let directory = try VehiclePhotoStore.attachmentsDirectory()
        defer { try? FileManager.default.removeItem(at: directory.appendingPathComponent(relativePath)) }

        assertPromisedClassApplied(to: directory, recorded: recorder.snapshot())
    }

    /// Asserts the promised class was applied to `url`: at least one recorded
    /// call names this file, and every call naming it used
    /// `completeUntilFirstUserAuthentication`. A removed applier leaves the file
    /// unrecorded and fails the first assert; a wrong class fails the second.
    private func assertPromisedClassApplied(to url: URL,
                                            recorded: [(String, URL)],
                                            file: StaticString = #filePath,
                                            line: UInt = #line) {
        let matching = recorded.filter { $0.1.standardizedFileURL == url.standardizedFileURL }
        XCTAssertFalse(matching.isEmpty,
                       "no file-protection call recorded for \(url.lastPathComponent)",
                       file: file, line: line)
        for entry in matching {
            XCTAssertEqual(
                entry.0, "completeUntilFirstUserAuthentication",
                "\(url.lastPathComponent) was applied class \(entry.0), not completeUntilFirstUserAuthentication",
                file: file, line: line)
        }
    }
}

/// A lock-guarded recorder of `(classRawValue, url)` pairs. The raw-value string
/// lets this test bundle observe the class without importing TankbookCore (the
/// TankbookTests bundle does not link the core package directly, PR.16b).
private final class ProtectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, URL)] = []

    func record(_ classRawValue: String, url: URL) {
        lock.lock(); defer { lock.unlock() }
        entries.append((classRawValue, url))
    }

    func snapshot() -> [(String, URL)] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}
