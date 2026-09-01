import Foundation
import Testing
@testable import TankbookCore

// PR.16b: the file-protection test PR.16 shipped asks the filesystem what it
// stored, and the iOS Simulator reports the class as a hard constant no matter
// what is set - so that test cannot fail on the only runtime CI has. These
// tests swap the shared `FileProtection.applier` seam for a recorder and assert
// the promised class was applied per file by the four core appliers (BlobStore,
// ArchiveFileIO, ConfigCache, VehicleCatalogCache), running on macOS where
// `swift test` executes and the platform attribute does not exist.
//
// `.serialized` so the tests do not fight over the single global seam. Other
// suites still run in parallel, but the recorder only asserts on this suite's
// own unique temporary paths, so a concurrent applier call from elsewhere
// cannot fail an assertion - and the default applier is a no-op on macOS, so a
// recorder installed during another suite's write is behaviourally identical.

@Suite("File protection seam (PR.16b)", .serialized)
struct FileProtectionSeamTests {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(FileProtection.Class, URL)] = []
        func record(_ protectionClass: FileProtection.Class, _ url: URL) {
            lock.lock(); defer { lock.unlock() }
            entries.append((protectionClass, url))
        }
        func snapshot() -> [(FileProtection.Class, URL)] {
            lock.lock(); defer { lock.unlock() }
            return entries
        }
    }

    private func tempDir(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    /// Installs `recorder` as the shared seam, runs `body`, restores the
    /// previous applier, and returns everything that was recorded.
    private func record(_ body: () throws -> Void) throws -> [(FileProtection.Class, URL)] {
        let recorder = Recorder()
        let original = FileProtection.applier
        FileProtection.applier = { protectionClass, url in recorder.record(protectionClass, url) }
        defer { FileProtection.applier = original }
        try body()
        return recorder.snapshot()
    }

    private func assertApplied(to url: URL, entries: [(FileProtection.Class, URL)]) {
        let matching = entries.filter { $0.1.standardizedFileURL == url.standardizedFileURL }
        #expect(!matching.isEmpty, "no file-protection call recorded for \(url.lastPathComponent)")
        for (protectionClass, _) in matching {
            #expect(
                protectionClass == .completeUntilFirstUserAuthentication,
                "\(url.lastPathComponent) was applied \(protectionClass), not .completeUntilFirstUserAuthentication")
        }
    }

    /// The atomic writers apply the class to the temp file before the rename, so
    /// the final file inherits it. Asserts at least one temp entry in `directory`
    /// carried the promised class.
    private func assertTempApplied(in directory: URL, entries: [(FileProtection.Class, URL)]) {
        let temps = entries.filter { entry in
            entry.1.lastPathComponent.contains(".tmp-")
                && entry.1.deletingLastPathComponent().standardizedFileURL
                    == directory.standardizedFileURL
        }
        #expect(!temps.isEmpty, "no temp-file protection call recorded under \(directory.path)")
        for (protectionClass, _) in temps {
            #expect(protectionClass == .completeUntilFirstUserAuthentication)
        }
    }

    // MARK: - BlobStore

    @Test func blobStoreSaveProtectsItsDirectory() throws {
        let directory = tempDir("fp-blob")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sha = BlobHash.sha256(Data("PR.16b".utf8))
        let entries = try record {
            try FileBackedBlobStore(directory: directory).save(Data("PR.16b".utf8), for: sha)
        }
        assertApplied(to: directory, entries: entries)
    }

    // MARK: - ConfigCache

    @Test func configCacheWriteProtectsDirectoryAndTempFile() throws {
        let directory = tempDir("fp-config")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheRecord = ConfigCacheRecord(
            document: Data("{}".utf8), signature: "sig", etag: nil,
            fetchedAt: Date(), activeBaseURL: nil, consecutiveFailures: 0)
        let entries = try record {
            try ConfigCacheFile.write(cacheRecord, directory: directory)
        }
        assertApplied(to: directory, entries: entries)
        assertTempApplied(in: directory, entries: entries)
    }

    // MARK: - VehicleCatalogCache

    @Test func vehicleCatalogCacheWriteProtectsDirectoryAndTempFile() throws {
        let directory = tempDir("fp-catalog")
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalogRecord = VehicleCatalogCacheRecord(packVersion: 1, entries: [], fetchedAt: Date(), missCount: 0)
        let entries = try record {
            try VehicleCatalogCacheFile.write(catalogRecord, directory: directory)
        }
        assertApplied(to: directory, entries: entries)
        assertTempApplied(in: directory, entries: entries)
    }

    // MARK: - ArchiveFileIO

    @Test func archiveAtomicWriteProtectsFinalFileAndTempFile() throws {
        let directory = tempDir("fp-archive")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manifest.json")
        let entries = try record {
            try ArchiveFileIO.atomicWrite(Data("{}".utf8), to: url)
        }
        assertApplied(to: url, entries: entries)
        assertTempApplied(in: directory, entries: entries)
    }
}
