import Foundation

/// Errors surfaced by `RemoteConfigFetcher`.
public enum RemoteConfigFetcherError: Error, Sendable, Equatable {
    /// The server answered with a status that is neither 2xx nor 304. The status
    /// is a machine value, not a domain value (docs/LOGGING.md hard rule 12).
    case unexpectedStatus(Int)
    /// The response body was not the documented envelope
    /// `{ document, signature, version }` (docs/API.md `GET /config`).
    case malformedEnvelope
}

/// The real config fetcher, over `TankbookHTTPClient` (docs/API.md ->
/// `GET /v1/config`). It sends `If-None-Match` when an etag is known and returns
/// nil on `304`, which the caller treats as "the held document stands", never as
/// a failure.
///
/// The base URL is read through a closure, not baked in at construction: config
/// is the one thing that can change the base URL, so the fetcher must follow the
/// resolved `apiBaseURL` (`ConfigStore.current`) rather than a fixed value
/// (docs/CONFIG.md -> "Guardrails on apiBaseUrl").
public struct RemoteConfigFetcher: ConfigFetcher {
    private let client: TankbookHTTPClient
    private let baseURLProvider: @Sendable () -> URL

    public init(client: TankbookHTTPClient, baseURLProvider: @escaping @Sendable () -> URL) {
        self.client = client
        self.baseURLProvider = baseURLProvider
    }

    public func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult? {
        var request = TankbookHTTPRequest(url: endpoint())
        if let etag {
            request.headers["If-None-Match"] = etag
        }

        let response = try await client.send(request)

        if response.status == 304 {
            return nil
        }
        guard (200...299).contains(response.status) else {
            throw RemoteConfigFetcherError.unexpectedStatus(response.status)
        }
        guard let body = response.body else {
            throw RemoteConfigFetcherError.malformedEnvelope
        }
        let envelope = try Self.parseEnvelope(body)
        return ConfigFetchResult(
            document: envelope.document,
            signature: envelope.signature,
            etag: response.value(forHeader: "ETag")
        )
    }

    /// `GET {base}/v1/config` (docs/API.md -> "Versioned surface": everything
    /// except `/health` lives under `/v1`).
    private func endpoint() -> URL {
        baseURLProvider().appendingPathComponent("v1").appendingPathComponent("config")
    }

    /// Decodes the wire envelope `{ document, signature, version }`. `document`
    /// is served verbatim (the exact bytes the server signed), so it is
    /// extracted from the raw bytes; `signature` is a scalar read through
    /// `JSONSerialization`. `version` is not needed here - the document carries
    /// its own, parsed during validation.
    private static func parseEnvelope(_ body: Data) throws -> (document: Data, signature: String) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let signature = object["signature"] as? String,
              let document = Self.rawValue(for: "document", in: body) else {
            throw RemoteConfigFetcherError.malformedEnvelope
        }
        return (document, signature)
    }

    /// Returns the raw JSON value bytes for a top-level object key. The document
    /// must not be round-tripped through a JSON object - re-serializing reorders
    /// keys and rewrites number tokens, breaking the Ed25519 signature over the
    /// original bytes (the same reason `ConfigCacheCodec` extracts the cached
    /// document verbatim).
    private static func rawValue(for key: String, in data: Data) -> Data? {
        var scanner = RawJSONScanner(bytes: [UInt8](data))
        return scanner.rawValue(for: key)
    }
}

/// A tiny cursor over raw JSON bytes that can return the exact source bytes of a
/// top-level object member's value without re-serializing. Used by
/// `RemoteConfigFetcher` to extract the signed document verbatim.
private struct RawJSONScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Returns the raw value bytes for the first top-level member named `key`.
    mutating func rawValue(for key: String) -> Data? {
        skipWhitespace()
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else { return nil }
        index += 1

        while true {
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "}") { return nil }
            guard bytes[index] == UInt8(ascii: "\"") else { return nil }
            let keyBytes = readStringBytes()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            skipWhitespace()

            let valueStart = index
            skipValue()
            if String(bytes: keyBytes, encoding: .utf8) == key {
                return Data(bytes[valueStart ..< index])
            }

            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                return nil
            } else {
                return nil
            }
        }
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, Self.isWhitespace(bytes[index]) {
            index += 1
        }
    }

    private mutating func readStringBytes() -> [UInt8] {
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
        return decoded
    }

    private mutating func skipValue() {
        guard index < bytes.count else { return }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            skipContainer(open: UInt8(ascii: "{"), close: UInt8(ascii: "}"))
        case UInt8(ascii: "["):
            skipContainer(open: UInt8(ascii: "["), close: UInt8(ascii: "]"))
        case UInt8(ascii: "\""):
            _ = readStringBytes()
        default:
            while index < bytes.count {
                let byte = bytes[index]
                let isDelimiter = byte == UInt8(ascii: ",")
                    || byte == UInt8(ascii: "}")
                    || byte == UInt8(ascii: "]")
                    || Self.isWhitespace(byte)
                if isDelimiter { break }
                index += 1
            }
        }
    }

    private mutating func skipContainer(open: UInt8, close: UInt8) {
        index += 1 // opening bracket
        while index < bytes.count {
            skipWhitespace()
            guard index < bytes.count else { return }
            if bytes[index] == close {
                index += 1
                return
            }
            if open == UInt8(ascii: "{") {
                guard bytes[index] == UInt8(ascii: "\"") else { return }
                _ = readStringBytes()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return }
                index += 1
                skipWhitespace()
            }
            skipValue()
            skipWhitespace()
            guard index < bytes.count else { return }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == close {
                index += 1
                return
            } else {
                return
            }
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
