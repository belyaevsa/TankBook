import Foundation

/// The on-disk cache envelope (docs/CONFIG.md -> "Where it is stored"):
///
///     Application Support/Tankbook/config.cache.json
///       { document, signature, etag, fetchedAt, activeBaseURL, consecutiveFailures }
///
/// `document` is the **raw served bytes verbatim**, never re-encoded: the
/// Ed25519 signature verifies only over exactly those bytes, and a future build
/// must be able to read keys this one does not know. The other fields are plain
/// scalars, so re-encoding them is lossless.
struct ConfigCacheRecord: Sendable, Equatable {
    var document: Data
    var signature: String
    var etag: String?
    var fetchedAt: Date
    var activeBaseURL: String?
    var consecutiveFailures: Int
}

enum ConfigCacheError: Error {
    case malformed
}

/// Serializes and parses the cache envelope, embedding the document's raw bytes
/// as a nested JSON value without round-tripping them through a JSON object
/// (which would reorder keys and rewrite number tokens, breaking the signature).
///
/// The cache file is deliberately **not** the GRDB database: it must be readable
/// before the database opens and must survive a failed database migration, so
/// this code path has no GRDB dependency at all.
enum ConfigCacheCodec {
    static let cacheFileName = "config.cache.json"

    // MARK: Encoding

    /// Encodes a record. The envelope's scalar fields are serialized with
    /// `JSONSerialization` (lossless for strings/numbers), and the document is
    /// spliced in verbatim between the opening brace and the first comma.
    static func encode(_ record: ConfigCacheRecord) -> Data {
        var meta: [String: Any] = [
            "signature": record.signature,
            "fetchedAt": Self.iso8601(record.fetchedAt),
            "consecutiveFailures": record.consecutiveFailures,
        ]
        meta["etag"] = record.etag ?? NSNull()
        meta["activeBaseURL"] = record.activeBaseURL ?? NSNull()

        // These types (String, Int, NSNull) can never fail to serialize.
        let metaData = (try? JSONSerialization.data(withJSONObject: meta)) ?? Data("{}".utf8)
        let metaText = String(decoding: metaData, as: UTF8.self)
        let inner = metaText.dropFirst().dropLast() // strip the surrounding braces

        var output = Data()
        output.append(contentsOf: Array("{\"document\":".utf8))
        output.append(record.document)
        output.append(contentsOf: Array(",".utf8))
        output.append(contentsOf: inner.utf8)
        output.append(contentsOf: Array("}".utf8))
        return output
    }

    // MARK: Decoding

    /// Decodes a cache file. Throws `ConfigCacheError.malformed` on any
    /// structural problem, which the caller treats as "no cache".
    static func decode(_ data: Data) throws -> ConfigCacheRecord {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigCacheError.malformed
        }
        let signature = object["signature"] as? String ?? ""
        let etag = object["etag"] as? String
        let activeBaseURL = object["activeBaseURL"] as? String
        let consecutiveFailures = (object["consecutiveFailures"] as? NSNumber)?.intValue ?? 0
        guard let fetchedAtText = object["fetchedAt"] as? String,
              let fetchedAt = Self.iso8601Date(fetchedAtText) else {
            throw ConfigCacheError.malformed
        }
        let document = try Self.extractDocument(from: data)
        return ConfigCacheRecord(
            document: document,
            signature: signature,
            etag: etag,
            fetchedAt: fetchedAt,
            activeBaseURL: activeBaseURL,
            consecutiveFailures: consecutiveFailures
        )
    }

    // MARK: Raw document extraction

    /// Locates the `document` member's value in the envelope and returns its
    /// exact bytes. The whole file has already passed `JSONSerialization`, so
    /// the scanner below only has to find byte ranges, not re-validate JSON.
    private static func extractDocument(from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        var index = 0
        skipWhitespace(in: bytes, index: &index)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else { throw ConfigCacheError.malformed }
        index += 1

        while true {
            skipWhitespace(in: bytes, index: &index)
            guard index < bytes.count else { throw ConfigCacheError.malformed }
            if bytes[index] == UInt8(ascii: "}") { break }

            guard bytes[index] == UInt8(ascii: "\"") else { throw ConfigCacheError.malformed }
            let key = readString(in: bytes, index: &index)

            skipWhitespace(in: bytes, index: &index)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ConfigCacheError.malformed }
            index += 1
            skipWhitespace(in: bytes, index: &index)

            let valueStart = index
            try skipValue(in: bytes, index: &index)
            if key == "document" {
                return Data(bytes[valueStart ..< index])
            }

            skipWhitespace(in: bytes, index: &index)
            guard index < bytes.count else { throw ConfigCacheError.malformed }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                break
            } else {
                throw ConfigCacheError.malformed
            }
        }
        throw ConfigCacheError.malformed
    }

    private static func skipWhitespace(in bytes: [UInt8], index: inout Int) {
        while index < bytes.count, isWhitespace(bytes[index]) {
            index += 1
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func readString(in bytes: [UInt8], index: inout Int) -> String {
        index += 1 // opening quote
        var decoded: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                break
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                if index < bytes.count {
                    decoded.append(bytes[index])
                    index += 1
                }
                continue
            }
            decoded.append(byte)
            index += 1
        }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    private static func skipValue(in bytes: [UInt8], index: inout Int) throws {
        guard index < bytes.count else { throw ConfigCacheError.malformed }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            try skipContainer(in: bytes, index: &index, open: UInt8(ascii: "{"), close: UInt8(ascii: "}"))
        case UInt8(ascii: "["):
            try skipContainer(in: bytes, index: &index, open: UInt8(ascii: "["), close: UInt8(ascii: "]"))
        case UInt8(ascii: "\""):
            _ = readString(in: bytes, index: &index)
        default:
            // number, true, false, null: consume until a delimiter.
            while index < bytes.count {
                let byte = bytes[index]
                let isDelimiter = byte == UInt8(ascii: ",")
                    || byte == UInt8(ascii: "}")
                    || byte == UInt8(ascii: "]")
                    || isWhitespace(byte)
                if isDelimiter {
                    break
                }
                index += 1
            }
        }
    }

    private static func skipContainer(in bytes: [UInt8], index: inout Int, open: UInt8, close: UInt8) throws {
        index += 1 // opening bracket
        while true {
            skipWhitespace(in: bytes, index: &index)
            guard index < bytes.count else { throw ConfigCacheError.malformed }
            if bytes[index] == close {
                index += 1
                return
            }
            if open == UInt8(ascii: "{") {
                // An object member: read the key, expect ':', then the value.
                guard bytes[index] == UInt8(ascii: "\"") else { throw ConfigCacheError.malformed }
                _ = readString(in: bytes, index: &index)
                skipWhitespace(in: bytes, index: &index)
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ConfigCacheError.malformed }
                index += 1
                skipWhitespace(in: bytes, index: &index)
            }
            try skipValue(in: bytes, index: &index)
            skipWhitespace(in: bytes, index: &index)
            guard index < bytes.count else { throw ConfigCacheError.malformed }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == close {
                index += 1
                return
            } else {
                throw ConfigCacheError.malformed
            }
        }
    }

    // MARK: Dates

    private static func iso8601(_ date: Date) -> String {
        // ISO8601DateFormatter rather than Date.ISO8601FormatStyle, because the
        // latter omits the "Z" when handed an explicit `.gmt` time zone - and
        // this value must round-trip through `iso8601Date` below.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func iso8601Date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

// MARK: - File storage

/// Reads and atomically writes the cache file. This is the only place the cache
/// directory and file name are known; `ConfigStore` passes the directory in.
enum ConfigCacheFile {
    /// Reads the cache record, returning nil when the file is absent or corrupt
    /// (docs/CONFIG.md -> a corrupt cache falls back cleanly, never crashes).
    static func read(directory: URL) -> ConfigCacheRecord? {
        let url = directory.appendingPathComponent(ConfigCacheCodec.cacheFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ConfigCacheCodec.decode(data)
    }

    /// Atomically writes a record: temp file first, then `replaceItemAt`, so a
    /// crash mid-write can never leave a truncated document that fails
    /// validation on next launch (docs/CONFIG.md -> "Where it is stored").
    static func write(_ record: ConfigCacheRecord, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        applyFileProtection(to: directory)

        let url = directory.appendingPathComponent(ConfigCacheCodec.cacheFileName)
        let tempURL = directory.appendingPathComponent("\(ConfigCacheCodec.cacheFileName).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = ConfigCacheCodec.encode(record)
        try data.write(to: tempURL, options: [.atomic])
        applyFileProtection(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    /// Excludes the cache from backups and applies the same Data Protection
    /// class as the database (docs/CONFIG.md -> "Threat: the cache file is
    /// tampered with", rule 2; docs/SECURITY.md). iOS-only: on macOS these
    /// attributes do not exist or do nothing, so the logic is compiled out and
    /// the surrounding read/write stays testable.
    private static func applyFileProtection(to url: URL) {
        #if os(iOS)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #endif
        FileProtection.protect(url)
    }
}
