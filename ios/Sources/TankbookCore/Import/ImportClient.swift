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
    /// The request could not reach the server because the device genuinely has
    /// no route to it (offline, the network path dropped, DNS failed, timeout).
    /// The named exception's network half - the rest of the app is unaffected.
    /// RV.68: ONLY this class maps to the offline state; nothing else may.
    case transportUnreachable
    /// The request was stopped before it had a conclusion (a cancelled
    /// `URLSession` task). Not a failure at all - it must never surface as an
    /// error state (docs/ERRORS.md -> Import wizard).
    case cancelled
    /// A transport failure that is not a connectivity signal (TLS, an unknown
    /// error type). The device's network was fine, so this is never "you need a
    /// connection" - that next step would send the user to fix something that
    /// is not broken (hard rule 7).
    case transportFailure
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
    public let director: ConfigTransportDirector
    /// The device identity for attribution when signed out (docs/API.md: a
    /// signed-out parse is stored under `X-Device-Id`). nil when unknown.
    public let deviceID: String?
    /// The facade that records `ImportTransportFailure` BEFORE the error is
    /// mapped (RV.68). nil in callers that have no log to hand; production
    /// always supplies one (ImportService).
    public let log: TankbookLog?
    /// ISO-8601 decoder for the parse responses.
    private let decoder: JSONDecoder

    public init(httpClient: TankbookHTTPClient, director: ConfigTransportDirector,
                deviceID: String?, log: TankbookLog? = nil) {
        self.httpClient = httpClient
        self.director = director
        self.deviceID = deviceID
        self.log = log
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// `GET /v1/import/formats` - the server-driven supported-source list. The
    /// source picker renders this response and nothing else.
    public func fetchFormats() async throws -> [ImportFormat] {
        let url = endpoint("import/formats")
        let response = try await send(TankbookHTTPRequest(url: url))
        return try decode([ImportFormat].self, from: response, url: url)
    }

    /// `POST /v1/import/parse` - uploads the declared format's file and returns
    /// candidates the device reviews (the server commits nothing). The format's
    /// display name is carried so a 422 can name the declared source ("this
    /// doesn't look like a My Fuel Manager export") instead of failing vaguely.
    public func parseFile(data: Data, fileName: String, format: ImportFormat) async throws -> ImportParseResponse {
        let url = endpoint("import/parse")
        let boundary = "tankbook-import-\(UUID().uuidString)"
        let body = Self.multipartBody(data: data, fileName: fileName,
                                      formatID: format.id, boundary: boundary)
        var request = TankbookHTTPRequest(url: url, method: "POST", body: body,
                                          timeoutInterval: TransportTimeouts.upload)
        request.headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        let response = try await send(request, declaredDisplayName: format.displayName)
        guard let body = response.body else { throw ImportClientError.invalidResponse }
        do {
            return try decoder.decode(ImportParseResponse.self, from: body)
        } catch {
            throw ImportClientError.invalidResponse
        }
    }

    /// `GET /v1/import/{importId}` - re-reads a stored parse so a review can be
    /// resumed after a crash or on another device.
    public func fetchParse(importId: String) async throws -> ImportParseResponse {
        let url = endpoint("import/\(importId)")
        let response = try await send(TankbookHTTPRequest(url: url))
        return try decode(ImportParseResponse.self, from: response, url: url)
    }

    /// `DELETE /v1/import/{importId}` - drops the stored parse early, idempotently
    /// (`204` whether or not it existed). Called when the user cancels at the
    /// preview gate; nothing else is written.
    public func deleteParse(importId: String) async throws {
        let url = endpoint("import/\(importId)")
        _ = try await send(TankbookHTTPRequest(url: url, method: "DELETE"))
    }

    // MARK: - Plumbing

    /// All import endpoints live under `/v1` like every other versioned surface
    /// (docs/API.md -> Ops: everything except `/health` lives under `/v1`; the
    /// backend routes import under `MapGroup("/v1")`). RV.68: this prefix was
    /// missing - the client asked the server for `/v1/import/formats`, which does
    /// not exist, so a healthy online device got a 404 that the old mapping
    /// rendered as the offline card.
    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    private func send(_ request: TankbookHTTPRequest,
                      declaredDisplayName: String? = nil) async throws -> TankbookHTTPResponse {
        var request = request
        if request.headers["X-Device-Id"] == nil, let deviceID {
            request.headers["X-Device-Id"] = deviceID
        }
        do {
            let response = try await httpClient.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch TankbookHTTPClientError.httpError(let status, let code, _, _) {
            // The host answered with a non-2xx import status - a response, never
            // a transport failure - mapped by its code when the server named one,
            // else per status below (a 422 carries the declared format's display
            // name so the message is specific, F7).
            await director.report(.response(status: status))
            throw Self.error(for: status, declaredDisplayName: declaredDisplayName, code: ServerErrorCode(raw: code))
        } catch is TankbookHTTPClientError {
            // Host-not-allowlisted / redirect loop: a real client bug or a
            // security violation, never an offline state.
            await director.report(.transportFailure)
            throw ImportClientError.client
        } catch {
            // RV.68: every non-HTTP error used to become `.transportUnreachable`
            // here, which the source screen rendered as "Importing needs a
            // connection" - a cancellation, a TLS failure and a decode all sent
            // the user to fix a connection that was not broken. The underlying
            // error is now classified, and its type and code are logged BEFORE
            // the mapping so the mapping is reconstructible from the log (this
            // row exists because nothing recorded which error occurred).
            let classification = TransportErrorClassifier.classify(error)
            if case .cancelled = classification {
                // A cancellation is not a failure at all: it must not surface as
                // an error state, and it is no evidence against the base URL
                // (docs/CONFIG.md) - so it is neither reported nor logged as one.
                throw ImportClientError.cancelled
            }
            if let log {
                log.emit(ImportTransportFailure(endpoint: request.url.path, error: error))
            }
            await director.report(.transportFailure)
            switch classification {
            case .connectivity:
                throw ImportClientError.transportUnreachable
            case .other:
                throw ImportClientError.transportFailure
            case .cancelled:
                preconditionFailure("handled above")
            }
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

    /// The per-error classification (docs/API.md, docs/ERRORS.md -> Import
    /// wizard): the server's `code` names the condition when it is one of this
    /// surface's own codes (415/422/404 carry meaning the status alone could
    /// blur), and an unknown or absent code falls back to the status-based
    /// classification (PR.9).
    static func error(for status: Int, declaredDisplayName: String?, code: ServerErrorCode? = nil) -> ImportClientError {
        switch code {
        case .importFormatUnsupported: return .unrecognisedFormat
        case .importMismatch: return .doesNotMatchDeclared(displayName: declaredDisplayName ?? "unknown")
        case .importNotFound: return .server(status: status)
        default: break
        }
        switch status {
        case 413: return .oversize
        case 415: return .unrecognisedFormat
        case 422: return .doesNotMatchDeclared(displayName: declaredDisplayName ?? "unknown")
        case 400: return .missingIdentity
        default: return .server(status: status)
        }
    }

    /// Builds the `multipart/form-data` body for `POST /v1/import/parse`: the
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
