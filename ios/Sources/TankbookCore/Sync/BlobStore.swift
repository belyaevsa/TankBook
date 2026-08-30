import CryptoKit
import Foundation

/// The local content-addressed cache for downloaded blobs (docs/SYNC.md: "the
/// device caches the file locally forever after - content addressing means no
/// revalidation, ever"). A key is the sha256, so a hit is proof the exact bytes
/// are already on disk and a miss needs a fetch.
public protocol BlobStore: Sendable {
    /// The cached bytes for `sha256`, or nil if not present.
    func data(for sha256: String) throws -> Data?
    /// Caches `data` under its `sha256` content address.
    func save(_ data: Data, for sha256: String) throws
    /// Removes the cached bytes for `sha256`, if present. The archive import
    /// uses it to roll the filesystem back when a transaction fails (a whole
    /// import that fails must leave nothing behind, docs/SCHEMA.md -> "Rejection
    /// is whole"). Content addressing makes removal safe: a byte-addressed cache
    /// is repopulated by re-fetch, never referenced by pointer.
    func remove(sha256: String) throws
}

extension BlobStore {
    /// Default no-op so existing conformers keep working; production and test
    /// stores override it.
    public func remove(sha256: String) throws {}
}

/// The production `BlobStore`: one file per blob, named by its sha256, under a
/// directory the app owns (the attachments directory - user data, so it stays
/// in device backups like the database; docs/SECURITY.md -> iOS table).
public struct FileBackedBlobStore: BlobStore, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(for sha256: String) -> URL {
        directory.appendingPathComponent(sha256)
    }

    public func data(for sha256: String) throws -> Data? {
        let url = url(for: sha256)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func save(_ data: Data, for sha256: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        // Docs/SECURITY.md promises the same Data Protection class as the
        // database on attachments; applied to the directory so files written
        // into it inherit it. Compiled out on macOS, where the attribute does
        // not exist (the core package runs its tests there).
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        try data.write(to: url(for: sha256), options: .atomic)
    }

    public func remove(sha256: String) throws {
        let url = url(for: sha256)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// The single sha256 helper for the blob pipeline (lowercase hex). Content
/// addressing is only a guarantee if the same hash is checked everywhere - the
/// write path computes it once, and verify-on-download compares against it.
public enum BlobHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Lazy download with verify-on-download (docs/SYNC.md -> Delivery). A cache hit
/// returns immediately - content addressing means no revalidation, ever. A miss
/// downloads, verifies the bytes hash to the requested sha256 (discarding them
/// on mismatch - never cached, never displayed), then caches and returns.
public struct LazyBlobFetcher: Sendable {
    public let transport: any BlobTransport
    public let store: any BlobStore

    public init(transport: any BlobTransport, store: any BlobStore) {
        self.transport = transport
        self.store = store
    }

    public func fetch(sha256: String) async throws -> Data {
        if let cached = try store.data(for: sha256) { return cached }
        let data = try await transport.download(sha256: sha256)
        guard BlobHash.sha256(data) == sha256 else {
            throw BlobSyncError.hashMismatch
        }
        try store.save(data, for: sha256)
        return data
    }
}
