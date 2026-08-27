import Foundation

/// The on-disk catalog cache envelope (docs/SYNC.md -> "Where the cache lives"):
///
///     Application Support/Tankbook/catalog.cache.json
///       { packVersion, entries, fetchedAt, missCount }
///
/// `entries` is the validated, resolved server-pack entry set - the full set
/// the server most recently told us about after applying the last delta, not a
/// delta itself. `missCount` is the device-local "model not found" tally
/// (docs/SYNC.md -> Curation feedback loop): a count only, never a search
/// string (hard rule 12).
struct VehicleCatalogCacheRecord: Codable, Equatable {
    var packVersion: Int
    var entries: [VehicleCatalogEntry]
    var fetchedAt: Date
    var missCount: Int
}

/// Serializes and parses the cache envelope. The cache file is deliberately
/// **not** the GRDB database: like the config cache it must be readable before
/// the database opens and must survive a failed database migration, so this
/// path has no GRDB dependency at all (docs/SYNC.md -> "Where the cache lives").
enum VehicleCatalogCacheFile {
    static let cacheFileName = "catalog.cache.json"

    /// Reads the cache record, returning nil when the file is absent or corrupt
    /// (docs/ERRORS.md -> Vehicle catalog updates: a truncated cache falls back
    /// to the bundled seed pack and refetches - never a crash).
    static func read(directory: URL) -> VehicleCatalogCacheRecord? {
        let url = directory.appendingPathComponent(cacheFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VehicleCatalogCacheRecord.self, from: data)
    }

    /// Atomically writes a record: temp file first, then `replaceItemAt`, so a
    /// crash mid-write can never leave a truncated pack that fails validation
    /// on next launch (docs/SYNC.md -> "Applying an update": atomic write).
    static func write(_ record: VehicleCatalogCacheRecord, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        applyAttributes(to: directory)

        let url = directory.appendingPathComponent(cacheFileName)
        let tempURL = directory.appendingPathComponent("\(cacheFileName).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = try JSONEncoder().encode(record)
        try data.write(to: tempURL, options: [.atomic])
        applyAttributes(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    /// Excludes the cache from backups - it is regenerable and is not user data
    /// (docs/SYNC.md -> "Where the cache lives") - and, on iOS, applies the
    /// same Data Protection class as the database (docs/SECURITY.md). The
    /// backup exclusion also works on macOS, so `swift test` asserts the flag
    /// on a real file; only the protection class is iOS-specific.
    static func applyAttributes(to url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
