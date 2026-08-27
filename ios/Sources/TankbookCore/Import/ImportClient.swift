import Foundation

// The import API client (docs/API.md -> Import parsing). Everything goes through
// `TankbookHTTPClient`, so the host allowlist and the host-bound Authorization
// apply to import exactly as they do to sync; the transport is injectable, so
// tests open no sockets (docs/TESTING.md). Parsing is hard rule 9's named
// exception - the ONLY part of import that needs a connection, and the rest of
// the app is untouched when it is unavailable (hard rule 1).

/// Errors the import client surfaces, each mapped from a specific wire status
/// (docs/ERRORS.md -> Import wizard). A 422 is never a generic failure: it
/// carries the display name of the format the user declared, so the UI can say
/// "this doesn't look like a My Fuel Manager export" and offer the picker again
/// (F7).
public enum ImportClientError: Error, Sendable, Equatable {
    /// The request could not reach the server (offline, DNS, timeout). The
    /// named exception's network half - the rest of the app is unaffected.
    case transportUnreachable
    /// The transport or host allowlist refused the request outright - a bug or
    /// a security violation, never the user's offline state.
    case client
    /// `413` - the file exceeds the 8 MB cap.
    case oversize
    /// `415` - an unrecognised format id was sent.
    case unrecognisedFormat
    /// `422` - the file does not look like the format the user declared.
    /// `displayName` is the declared format's name, so the message is specific.
    case doesNotMatchDeclared(displayName: String)
    /// `400` - neither a bearer token nor an X-Device-Id was available to
    /// attribute the parse.
    case missingIdentity
    /// Any other non-2xx.
    case server(status: Int)
    /// The response body was not the expected JSON.
    case invalidResponse
}

/// The host-bound client for the three import endpoints. Public so the app
/// target can build it over its own transport and session store.
public struct ImportClient: Sendable {
    public let httpClient: TankbookHTTPClient
    public let baseURL: URL
    /// The device identity for attribution when signed out (docs/API.md: a
    /// signed-out parse is stored under `X-Device-Id`). nil when unknown.
    public let deviceID: String?
    /// ISO-8601 decoder for the parse responses.
    private let decoder: JSONDecoder

    public init(httpClient: TankbookHTTPClient, baseURL: URL, deviceID: String?) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.deviceID = deviceID
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// `GET /import/formats` - the server-driven supported-source list. The
    /// source picker renders this response and nothing else.
    public func fetchFormats() async throws -> [ImportFormat] {
        let url = baseURL.appendingPathComponent("import/formats")
        let response = try await send(TankbookHTTPRequest(url: url))
        return try decode([ImportFormat].self, from: response, url: url)
    }

    /// `POST /import/parse` - uploads the declared format's file and returns
    /// candidates the device reviews (the server commits nothing). The format's
    /// display name is carried so a 422 can name the declared source ("this
    /// doesn't look like a My Fuel Manager export") instead of failing vaguely.
    public func parseFile(data: Data, fileName: String, format: ImportFormat) async throws -> ImportParseResponse {
        let url = baseURL.appendingPathComponent("import/parse")
        let boundary = "tankbook-import-\(UUID().uuidString)"
        let body = Self.multipartBody(data: data, fileName: fileName,
                                      formatID: format.id, boundary: boundary)
        var request = TankbookHTTPRequest(url: url, method: "POST", body: body)
        request.headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        let response = try await send(request)
        guard (200...299).contains(response.status) else {
            throw Self.error(for: response.status, declaredDisplayName: format.displayName)
        }
        guard let body = response.body else { throw ImportClientError.invalidResponse }
        do {
            return try decoder.decode(ImportParseResponse.self, from: body)
        } catch {
            throw ImportClientError.invalidResponse
        }
    }

    /// `GET /import/{importId}` - re-reads a stored parse so a review can be
    /// resumed after a crash or on another device.
    public func fetchParse(importId: String) async throws -> ImportParseResponse {
        let url = baseURL.appendingPathComponent("import/\(importId)")
        let response = try await send(TankbookHTTPRequest(url: url))
        return try decode(ImportParseResponse.self, from: response, url: url)
    }

    /// `DELETE /import/{importId}` - drops the stored parse early, idempotently
    /// (`204` whether or not it existed). Called when the user cancels at the
    /// preview gate; nothing else is written.
    public func deleteParse(importId: String) async throws {
        let url = baseURL.appendingPathComponent("import/\(importId)")
        _ = try await send(TankbookHTTPRequest(url: url, method: "DELETE"))
    }

    // MARK: - Plumbing

    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        var request = request
        if request.headers["X-Device-Id"] == nil, let deviceID {
            request.headers["X-Device-Id"] = deviceID
        }
        do {
            return try await httpClient.send(request)
        } catch is TankbookHTTPClientError {
            // Host-not-allowlisted / redirect loop: a real client bug or a
            // security violation, never an offline state.
            throw ImportClientError.client
        } catch {
            throw ImportClientError.transportUnreachable
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: TankbookHTTPResponse,
                                      url: URL) throws -> T {
        guard (200...299).contains(response.status) else {
            throw Self.error(for: response.status, declaredDisplayName: nil)
        }
        guard let body = response.body else { throw ImportClientError.invalidResponse }
        do {
            return try decoder.decode(type, from: body)
        } catch {
            throw ImportClientError.invalidResponse
        }
    }

    /// The per-status error (docs/API.md, docs/ERRORS.md -> Import wizard):
    /// 413 oversize, 415 unrecognised format, 422 doesn't match the declared
    /// format (named specifically, F7), 400 missing identity. Every other
    /// non-2xx is a generic server status - never a lie about what happened
    /// (a specific message only where the server named one).
    static func error(for status: Int, declaredDisplayName: String?) -> ImportClientError {
        switch status {
        case 413: return .oversize
        case 415: return .unrecognisedFormat
        case 422: return .doesNotMatchDeclared(displayName: declaredDisplayName ?? "unknown")
        case 400: return .missingIdentity
        default: return .server(status: status)
        }
    }

    /// Builds the `multipart/form-data` body for `POST /import/parse`: the
    /// `format` field carries the user's declaration, `file` the export.
    static func multipartBody(data: Data, fileName: String, formatID: String,
                              boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"format\"\r\n\r\n")
        append("\(formatID)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }
}
