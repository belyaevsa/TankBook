import Foundation

// The feedback API client (docs/API.md -> Feedback: `POST /feedback`, public
// with an optional bearer). Built against the documented contract; the server
// half (PJ.20a) is filed separately. Everything goes through
// `TankbookHTTPClient`, so the host allowlist and the host-bound Authorization
// apply here exactly as they do to sync and import. A signed-out device
// attributes the case via `X-Device-Id` (the same per-install id the import
// path uses for rate-limit attribution).

/// Errors the feedback client surfaces, each mapped from a specific wire status
/// (docs/API.md -> Feedback, docs/ERRORS.md -> About & feedback).
public enum FeedbackClientError: Error, Sendable, Equatable {
    /// The request could not reach the server (offline, DNS, timeout). The case
    /// stays queued and retries later (docs/ERRORS.md: "sends automatically").
    case transportUnreachable
    /// The transport or host allowlist refused the request outright - a bug or
    /// a security violation, never the user's offline state.
    case client
    /// `429` - rate limited per device/IP. The case stays queued for the next
    /// window (docs/ERRORS.md: "queued for tomorrow").
    case rateLimited
    /// Any other non-202 status.
    case server(status: Int)
}

/// The host-bound client for `POST /feedback`.
public struct FeedbackClient: Sendable {
    public let httpClient: TankbookHTTPClient
    public let director: ConfigTransportDirector
    /// The device identity for rate-limit attribution when signed out
    /// (docs/API.md). nil when unknown.
    public let deviceID: String?

    public init(httpClient: TankbookHTTPClient, director: ConfigTransportDirector,
                deviceID: String?) {
        self.httpClient = httpClient
        self.director = director
        self.deviceID = deviceID
    }

    /// Posts one case. Success is `202` (accepted); `429` maps to `.rateLimited`,
    /// any other non-202 to `.server(status:)`.
    public func send(_ payload: FeedbackPayload) async throws {
        let url = director.baseURL().appendingPathComponent("v1").appendingPathComponent("feedback")
        var request = TankbookHTTPRequest(url: url, method: "POST")
        request.headers["Content-Type"] = "application/json"
        request.body = try JSONEncoder().encode(payload)
        if request.headers["X-Device-Id"] == nil, let deviceID {
            request.headers["X-Device-Id"] = deviceID
        }

        let response: TankbookHTTPResponse
        do {
            response = try await httpClient.send(request)
            await director.report(.response(status: response.status))
        } catch is TankbookHTTPClientError {
            await director.report(.transportFailure)
            throw FeedbackClientError.client
        } catch {
            await director.report(.transportFailure)
            throw FeedbackClientError.transportUnreachable
        }

        switch response.status {
        case 202: return
        case 429: throw FeedbackClientError.rateLimited
        default: throw FeedbackClientError.server(status: response.status)
        }
    }
}
