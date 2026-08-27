import Foundation

// File discipline for the archive (docs/SCHEMA.md -> "the same discipline
// applies to anything you write to disk"): every archive file is written
// atomically (temp file + rename) so a crash mid-write can never leave a
// truncated file that later fails to parse, and files the app owns carry the
// same Data Protection + backup-exclusion attributes as the config cache
// (docs/CONFIG.md -> "Where it is stored", docs/SECURITY.md).

enum ArchiveFileIO {
    /// Atomically writes `data` to `url`: temp file first, then rename.
    /// `isExcludedFromBackup` and the Data Protection class are applied the
    /// same way ConfigCacheFile does - iOS-only, compiled out on macOS so
    /// `swift test` stays green.
    static func atomicWrite(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try data.write(to: tempURL, options: [.atomic])
        applyProtection(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        applyProtection(to: url)
    }

    /// The content-addressed blob directory inside an archive.
    static func attachmentsDirectory(in archive: URL) -> URL {
        archive.appendingPathComponent("attachments", isDirectory: true)
    }

    static func blobURL(sha256: String, in archive: URL) -> URL {
        attachmentsDirectory(in: archive).appendingPathComponent(sha256)
    }

    /// A plain, parseable JSON value written atomically.
    static func atomicWriteJSON(_ value: JSONValue, to url: URL) throws {
        try atomicWrite(try value.jsonData(), to: url)
    }

    static func readData(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw VehicleArchiveError.underlying("could not read \(url.lastPathComponent): \(error)")
        }
    }

    private static func applyProtection(to url: URL) {
        #if os(iOS)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
