import Foundation

// MARK: - P6.3 the /extract client (docs/API.md -> "LLM gateway (Pro)").
//
// The device side of P4.10. The server ships (P4.10) and its status codes are
// already classified as `SyncServerError` (P6.11) - this client CONSUMES that
// classification, it never re-classifies:
//
//   402 -> .tierRefused, 429 -> .rateLimited(retryAfterSeconds:),
//   426 -> .upgradeRequired, unknown 4xx -> .refused(status:),
//   transport/5xx -> .transportUnavailable.
//
// The device rules that live here: the request carries the downscaled,
// JPEG-compressed rendition (`GatewayRendition`), and the envelope is a
// ceiling, not a target.

/// The seam an extract call crosses. The real implementation is
/// `RemoteGatewayExtractTransport`; tests inject a recording or slow fake so
/// the budget and error behaviour are provable without sockets
/// (docs/TESTING.md).
public protocol GatewayExtractTransport: Sendable {
    func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction
}

/// The production transport: `POST /v1/extract` over the host-bound
/// `TankbookHTTPClient`, so the bearer token and allowlist rules
/// (docs/SECURITY.md) apply exactly as they do for auth and sync.
public struct RemoteGatewayExtractTransport: GatewayExtractTransport {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider)
        self.director = director
    }

    public func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        let body = try encode(request)
        var http = TankbookHTTPRequest(url: endpoint("extract"), method: "POST", body: body)
        http.headers["Content-Type"] = "application/json"

        let response: TankbookHTTPResponse
        do {
            response = try await client.send(http)
            await director.report(.response(status: response.status))
        } catch {
            // The allowlist refusal and any socket-level failure are the same
            // survival shape: the on-device result stands (F4, S7) - and both
            // are evidence the host was unreachable.
            await director.report(.transportFailure)
            throw SyncServerError.transportUnavailable
        }

        switch response.status {
        case 200...299:
            guard let body = response.body else { throw GatewayExtractError.invalidResponse }
            return try GatewayExtraction.decode(body)
        case 402:
            throw SyncServerError.tierRefused
        case 429:
            throw SyncServerError.rateLimited(
                retryAfterSeconds: response.value(forHeader: "Retry-After").flatMap(Int.init))
        case 426:
            throw SyncServerError.upgradeRequired
        case 400...499:
            // A gate this client version does not know about (P6.11): reported
            // as what it is, never as a generic failure (JOURNEYS F7).
            throw SyncServerError.refused(status: response.status)
        default:
            // 5xx and anything non-HTTP-shaped: the server is having a
            // problem, which is the F4 fallback - the on-device result stands.
            throw SyncServerError.transportUnavailable
        }
    }

    // MARK: - Encoding

    private func encode(_ request: GatewayExtractRequest) throws -> Data {
        let base64 = request.imageJPEG.base64EncodedString()
        // The 4 MB cap is on the base64 image (docs/API.md). The rendition is
        // tuned far below it, so tripping it is a bug - refuse locally rather
        // than let the server answer 413.
        if base64.count > GatewayRendition.envelopeCapBytes {
            throw GatewayExtractError.envelopeTooLarge
        }

        var hintsObject: [String: JSONValue] = [:]
        if let currency = request.hints.currency { hintsObject["currency"] = .string(currency) }
        if let locale = request.hints.locale { hintsObject["locale"] = .string(locale) }
        if !request.hints.vehicleFuelKinds.isEmpty {
            hintsObject["vehicleFuelKinds"] = .array(request.hints.vehicleFuelKinds.map(JSONValue.string))
        }

        var object: [String: JSONValue] = [
            "kind": .string(request.kind),
            "image": .string(base64)
        ]
        if !hintsObject.isEmpty { object["hints"] = .object(hintsObject) }
        return try JSONValue.object(object).jsonData()
    }

    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }
}
