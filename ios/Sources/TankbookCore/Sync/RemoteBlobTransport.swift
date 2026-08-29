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
        switch response.status {
        case 200:
            return try decodeBegin(response.body)
        case 401:
            throw BlobSyncError.authExpired
        case 413:
            throw BlobSyncError.sizeExceeded
        case 429:
            throw BlobSyncError.quotaExceeded
        default:
            throw BlobSyncError.invalidResponse
        }
    }

    public func put(_ data: Data, to url: URL, contentType: String) async throws {
        var request = TankbookHTTPRequest(url: url, method: "PUT", body: data)
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
        let response = try await send(request)
        guard (200...299).contains(response.status) else {
            if response.status == 401 { throw BlobSyncError.authExpired }
            throw BlobSyncError.invalidResponse
        }
    }

    public func download(sha256: String) async throws -> Data {
        let request = TankbookHTTPRequest(url: endpoint("blobs/\(sha256)"), method: "GET")
        // The client follows the 302 to the short-lived presigned GET; the
        // redirect hop carries no bearer token (docs/SECURITY.md).
        let response = try await send(request)
        switch response.status {
        case 200:
            guard let body = response.body else { throw BlobSyncError.invalidResponse }
            return body
        case 401:
            throw BlobSyncError.authExpired
        case 404:
            throw BlobSyncError.notFound
        default:
            throw BlobSyncError.invalidResponse
        }
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
        } catch {
            await director.report(.transportFailure)
            throw BlobSyncError.transportUnavailable
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
