import Foundation

/// The production `BlobTransport` (docs/API.md -> Attachments). `begin`,
/// `commit` and `download` go through the host-bound `TankbookHTTPClient` so the
/// bearer token and allowlist rules (docs/SECURITY.md) apply exactly as they do
/// for auth and sync. The presigned PUT is the one deliberate exception: the
/// presigned URL is a storage host, unauthenticated by design (the signature IS
/// the credential), so it is sent through the raw transport with no bearer token
/// and no allowlist check - putting it through the host-bound client would both
/// refuse it and leak the token to a host it was never bound to.
public struct RemoteBlobTransport: BlobTransport, Sendable {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector
    private let raw: any TankbookHTTPTransport

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider,
                refresher: (any SessionRefreshing)? = nil) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider,
                                         refresher: refresher)
        self.director = director
        self.raw = transport
    }

    public func begin(sha256: String, size: Int, contentType: String) async throws -> BlobBeginResult {
        let body = try JSONValue.object([
            "sha256": .string(sha256),
            "size": .number(String(size)),
            "contentType": .string(contentType)
        ]).jsonData()
        var request = TankbookHTTPRequest(url: endpoint("blobs/begin"), method: "POST", body: body)
        request.headers["Content-Type"] = "application/json"
        let response = try await send(request)
        return try decodeBegin(response.body)
    }

    public func put(_ data: Data, to url: URL, contentType: String) async throws {
        // The upload carries megabytes over a mobile uplink, so it asks for the
        // long budget explicitly rather than inheriting the JSON read timeout.
        var request = TankbookHTTPRequest(url: url, method: "PUT", body: data,
                                          timeoutInterval: TransportTimeouts.upload)
        request.headers["Content-Type"] = contentType
        let response: TankbookHTTPResponse
        do {
            response = try await raw.execute(request)
        } catch {
            throw BlobSyncError.transportUnavailable
        }
        guard (200...299).contains(response.status) else { throw BlobSyncError.invalidResponse }
    }

    public func commit(sha256: String) async throws {
        let body = try JSONValue.object(["sha256": .string(sha256)]).jsonData()
        var request = TankbookHTTPRequest(url: endpoint("blobs/commit"), method: "POST", body: body)
        request.headers["Content-Type"] = "application/json"
        _ = try await send(request)
    }

    public func download(sha256: String) async throws -> Data {
        let request = TankbookHTTPRequest(url: endpoint("blobs/\(sha256)"), method: "GET")
        // The client follows the 302 to the short-lived presigned GET; the
        // redirect hop carries no bearer token (docs/SECURITY.md).
        let response = try await send(request)
        guard let body = response.body else { throw BlobSyncError.invalidResponse }
        return body
    }

    // MARK: - HTTP

    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        do {
            let response = try await client.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch SessionRefresherError.authExpired {
            // The host answered (401, then a failed refresh). Session gone,
            // base URL fine - a response, never evidence the URL is wrong.
            await director.report(.response(status: 401))
            throw BlobSyncError.authExpired
        } catch TankbookHTTPClientError.httpError(let status, let code, _, _) {
            // The host answered with a non-2xx blob status - a response, never
            // a transport failure; the per-code/per-status error is docs/API.md's.
            await director.report(.response(status: status))
            throw Self.error(for: status, code: ServerErrorCode(raw: code))
        } catch {
            await director.report(.transportFailure)
            throw BlobSyncError.transportUnavailable
        }
    }

    /// Maps a non-2xx to its `BlobSyncError`: the server's `code` names the
    /// condition when it is one of this surface's own codes; an unknown or
    /// absent code falls back to the status-based classification (PR.9).
    private static func error(for status: Int, code: ServerErrorCode? = nil) -> BlobSyncError {
        switch code {
        case .tokenInvalid: return .authExpired
        case .blobNotFound: return .notFound
        case .payloadTooLarge: return .sizeExceeded
        case .blobQuotaExceeded: return .quotaExceeded
        default: break
        }
        switch status {
        case 401: return .authExpired
        case 404: return .notFound
        case 413: return .sizeExceeded
        case 429: return .quotaExceeded
        default: return .invalidResponse
        }
    }

    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    private func decodeBegin(_ data: Data?) throws -> BlobBeginResult {
        guard let data else { throw BlobSyncError.invalidResponse }
        let tree = try JSONValue.parse(data)
        guard let status = tree.objectValue?["status"]?.stringValue else {
            throw BlobSyncError.invalidResponse
        }
        switch status {
        case "exists":
            return .exists
        case "upload":
            guard let raw = tree.objectValue?["url"]?.stringValue,
                  let url = URL(string: raw) else { throw BlobSyncError.invalidResponse }
            let expiresAt = tree.objectValue?["expiresAt"]?.stringValue
                .flatMap(PayloadFormat.date(from:))
            return .upload(url: url, expiresAt: expiresAt)
        default:
            throw BlobSyncError.invalidResponse
        }
    }
}
