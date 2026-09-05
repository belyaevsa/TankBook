import Foundation

// MARK: - RV.44 the delivery-outbox client (docs/API.md "Delivery outbox")
//
// The device drains its own outbox on launch/foreground and acks each collected
// row. The drain is READ-ONLY - the ack is a separate DELETE, so a device that
// dies between read and ack re-drains the same rows on its next launch
// (at-least-once, and the inbox dedupes by row id). Everything goes through
// `TankbookHTTPClient`, so the host allowlist and host-bound Authorization apply
// exactly as they do to sync, auth and the gateway; the transport is injectable
// for a plain `swift test` (docs/TESTING.md).

/// One drained outbox entry: the row id (for ack and dedupe) and the decoded
/// payload.
public struct GatewayOutboxEntry: Sendable, Equatable {
    public var id: UUID
    public var payload: GatewayOutboxPayload

    public init(id: UUID, payload: GatewayOutboxPayload) {
        self.id = id
        self.payload = payload
    }
}

/// Errors the outbox client surfaces. A drain is best-effort - the app swallows
/// these and simply tries again on the next launch - so the cases are the honest
/// shape of "could not drain", never a user-facing gate (hard rule 1).
public enum GatewayOutboxError: Error, Sendable, Equatable {
    /// Offline, DNS or timeout: nothing to do but be online again.
    case transportUnreachable
    /// The host allowlist or transport refused outright - a client bug.
    case client
    /// 401 - the session is gone; drain silently skips until sign-in.
    case unauthorized
    /// Any other non-2xx.
    case server(status: Int)
    /// The response was not the expected JSON.
    case invalidResponse
}

/// The host-bound client for `GET /v1/outbox` (drain) and `DELETE
/// /v1/outbox/{id}` (ack). Public so the app target builds it over its own
/// transport and session store.
public struct GatewayOutboxClient: Sendable {
    public let httpClient: TankbookHTTPClient
    public let director: ConfigTransportDirector

    public init(httpClient: TankbookHTTPClient, director: ConfigTransportDirector) {
        self.httpClient = httpClient
        self.director = director
    }

    /// `GET /v1/outbox` - the device's pending rows, oldest first, each payload
    /// base64-decoded and parsed. Read-only: nothing is deleted here.
    public func drain() async throws -> [GatewayOutboxEntry] {
        let url = endpoint("outbox")
        let response = try await send(TankbookHTTPRequest(url: url))
        guard let body = response.body else { throw GatewayOutboxError.invalidResponse }
        let wire: DrainPayload
        do {
            wire = try JSONDecoder().decode(DrainPayload.self, from: body)
        } catch {
            throw GatewayOutboxError.invalidResponse
        }
        return try wire.items.map { item in
            guard let bytes = Data(base64Encoded: item.payload) else {
                throw GatewayOutboxError.invalidResponse
            }
            let payload = try GatewayOutboxPayload.decode(bytes)
            return GatewayOutboxEntry(id: item.id, payload: payload)
        }
    }

    /// `DELETE /v1/outbox/{id}` - acks one collected row, idempotently (204
    /// whether or not it still existed). Scoped server-side to the caller's own
    /// device, so a foreign id deletes nothing.
    public func ack(id: UUID) async throws {
        let url = endpoint("outbox/\(id.uuidString.lowercased())")
        _ = try await send(TankbookHTTPRequest(url: url, method: "DELETE"))
    }

    // MARK: - Plumbing

    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        do {
            let response = try await httpClient.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch SessionRefresherError.authExpired {
            await director.report(.response(status: 401))
            throw GatewayOutboxError.unauthorized
        } catch TankbookHTTPClientError.httpError(let status, let code, _, _) {
            await director.report(.response(status: status))
            throw Self.error(for: status, code: ServerErrorCode(raw: code))
        } catch is TankbookHTTPClientError {
            await director.report(.transportFailure)
            throw GatewayOutboxError.client
        } catch {
            await director.report(.transportFailure)
            throw GatewayOutboxError.transportUnreachable
        }
    }

    static func error(for status: Int, code: ServerErrorCode? = nil) -> GatewayOutboxError {
        switch code {
        case .tokenInvalid: return .unauthorized
        default: break
        }
        switch status {
        case 401: return .unauthorized
        default: return .server(status: status)
        }
    }

    private struct DrainPayload: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let id: UUID
        let payload: String
    }
}
