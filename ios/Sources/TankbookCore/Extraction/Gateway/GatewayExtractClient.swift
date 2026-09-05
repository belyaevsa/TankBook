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

/// The device-side arming policy for `/extract` (docs/API.md -> "The device's
/// side of `/extract`", RV.26): the cloud gateway is armed only when the
/// session can actually authenticate. A guest has no session and correctly
/// gets no gateway; a session whose refresh was rejected is marked
/// `authExpired` and must not be armed, because arming it uploads the image
/// for a guaranteed 401. Existence alone is not enough - that is exactly the
/// defect RV.26 fixed (`load() != nil` let a dead session through).
public enum GatewayArming {
    /// Whether the gateway should be armed for a capture. The `authExpired`
    /// mark is checked first: it is the authoritative "cannot authenticate"
    /// signal, and a stale mark must never be outlived by a leftover credential.
    public static func shouldArm(sessionStore: any SessionStore) -> Bool {
        guard !((try? sessionStore.isAuthExpired()) ?? false) else { return false }
        return (try? sessionStore.load()) != nil
    }
}

/// The production transport: `POST /v1/extract` over the host-bound
/// `TankbookHTTPClient`, so the bearer token and allowlist rules
/// (docs/SECURITY.md) apply exactly as they do for auth and sync.
public struct RemoteGatewayExtractTransport: GatewayExtractTransport {
    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector

    public init(director: ConfigTransportDirector,
                transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider,
                refresher: (any SessionRefreshing)? = nil) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider,
                                         refresher: refresher)
        self.director = director
    }

    public func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        // docs/API.md -> "Retries are the device's business, not the user's:
        // one silent retry at most, never a dialog." Only the transient class
        // (offline, 5xx) retries, once, then the failure surfaces. A refusal
        // (402/429/426/unknown 4xx) surfaces immediately - retrying it would
        // just be refused again, and the on-device result already stands (F4).
        do {
            return try await perform(request)
        } catch SyncServerError.transportUnavailable {
            return try await perform(request)
        }
    }

    private func perform(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        let body = try encode(request)
        var http = TankbookHTTPRequest(url: endpoint("extract"), method: "POST", body: body)
        http.headers["Content-Type"] = "application/json"

        let response: TankbookHTTPResponse
        do {
            response = try await client.send(http)
            await director.report(.response(status: response.status))
        } catch SessionRefresherError.authExpired {
            // The host answered 401, then the refresh's own non-2xx: the session
            // is gone for good (RV.26). This is an auth event, never a transient
            // failure - mapping it to `transportUnavailable` would trigger the
            // one silent retry against a token the server has already rejected,
            // and it would hide the "sign in again" next step from the surface.
            await director.report(.response(status: 401))
            throw SyncServerError.authExpired
        } catch TankbookHTTPClientError.httpError(let status, _, let retryAfterSeconds) {
            // The host answered with a non-2xx extract status - a response,
            // never a transport failure - classified as SyncServerError below
            // (the classification this client CONSUMES, P6.11).
            await director.report(.response(status: status))
            throw Self.error(for: status, retryAfterSeconds: retryAfterSeconds)
        } catch {
            // The allowlist refusal and any socket-level failure are the same
            // survival shape: the on-device result stands (F4, S7) - and both
            // are evidence the host was unreachable.
            await director.report(.transportFailure)
            throw SyncServerError.transportUnavailable
        }

        guard let body = response.body else { throw GatewayExtractError.invalidResponse }
        return try GatewayExtraction.decode(body)
    }

    /// The P6.11 classification (docs/API.md -> LLM gateway): 401 -> auth (RV.65
    /// - a 401 that outlived refresh-and-retry is a session the server rejects,
    /// exactly like sync's), 402 -> tier, 429 -> rate limited with the server's
    /// own wait, 426 -> upgrade, unknown 4xx -> refusal, 5xx -> transport (so
    /// the one silent retry in `extract` fires only on the transient class).
    private static func error(for status: Int, retryAfterSeconds: Int?) -> SyncServerError {
        switch status {
        case 401:
            return .authExpired
        case 402:
            return .tierRefused
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfterSeconds)
        case 426:
            return .upgradeRequired
        case 400...499:
            // A gate this client version does not know about (P6.11): reported
            // as what it is, never as a generic failure (JOURNEYS F7).
            return .refused(status: status)
        default:
            // 5xx and anything non-HTTP-shaped: the server is having a
            // problem, which is the F4 fallback - the on-device result stands.
            return .transportUnavailable
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
        if let captureId = request.captureId { object["captureId"] = .string(captureId) }
        if !hintsObject.isEmpty { object["hints"] = .object(hintsObject) }
        return try JSONValue.object(object).jsonData()
    }

    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }
}
