import Foundation

/// Failures surfaced by the shared token refresher (docs/PRACTICES.md S7,
/// docs/API.md -> Auth). A refresh failure is either the session is gone for
/// good (`authExpired`) or the server could not be reached
/// (`transportUnavailable`) - the distinction is load-bearing because the two
/// have opposite next steps: sign in again, or wait and retry.
public enum SessionRefresherError: Error, Sendable, Equatable {
    /// The refresh token was rejected (unknown, expired, reused-rotated) or
    /// there was no session to refresh. The session has been cleared; the user
    /// must sign in again. Never surfaced as "update the app".
    case authExpired
    /// The refresh request could not reach the server. The session is intact;
    /// the caller treats it as an ordinary outage (S7), never as an expiry.
    case transportUnavailable
}

/// The single shared token-refresh seam (docs/PRACTICES.md S7, PR.1). An actor
/// so a 401 storm - many `TankbookHTTPClient` owners failing at once - collapses
/// to ONE in-flight refresh: the server rotates refresh tokens and revokes the
/// chain on reuse, so two racing refreshes sign the user out ("randomly signed
/// out"). Concurrent callers await the one in-flight task rather than starting
/// a second.
public protocol SessionRefreshing: Sendable {
    /// Refreshes once, persists the rotated pair, and returns the new access
    /// token. Concurrent callers await the same in-flight refresh. Throws
    /// `SessionRefresherError.authExpired` (session cleared) or
    /// `.transportUnavailable` (session intact).
    func refresh() async throws -> String
}

/// The production refresher: posts `POST /auth/refresh` directly, persists the
/// rotated pair to the `SessionStore`, and returns the new access token. The
/// refresh request goes through a `TankbookHTTPClient` built WITHOUT a refresher
/// of its own - a 401 here is an outcome to classify, never a second refresh -
/// and without a token provider, because the refresh token rides in the body,
/// not in `Authorization` (docs/API.md -> Auth).
public actor SessionRefresher: SessionRefreshing {
    private let baseURLProvider: @Sendable () -> URL
    private let transport: any TankbookHTTPTransport
    private let sessionStore: any SessionStore
    private let client: TankbookHTTPClient
    private var inFlight: Task<String, Error>?

    public init(baseURLProvider: @escaping @Sendable () -> URL,
                transport: any TankbookHTTPTransport, sessionStore: any SessionStore) {
        self.baseURLProvider = baseURLProvider
        self.transport = transport
        self.sessionStore = sessionStore
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: NilTokenProvider())
    }

    public func refresh() async throws -> String {
        if let inFlight {
            return try await inFlight.value
        }
        // The base URL is read per refresh, never captured at construction, so
        // the refresher follows a promoted or reverted apiBaseURL (docs/CONFIG.md
        // -> "Base URL per operation"). The refresher does not report its own
        // outcome: it only runs nested inside a transport's 401 replay, and that
        // transport reports the request the refresher was serving.
        let baseURL = baseURLProvider()
        let task = Task { () async throws -> String in
            try await Self.performRefresh(baseURL: baseURL, client: self.client,
                                          sessionStore: self.sessionStore)
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    // MARK: - The refresh itself

    /// Runs the raw refresh POST. Static so it runs off the actor, on the
    /// values captured by the task - the actor only coordinates the in-flight
    /// gate and never blocks on the network itself.
    private static func performRefresh(baseURL: URL, client: TankbookHTTPClient,
                                       sessionStore: any SessionStore) async throws -> String {
        guard let session = try? sessionStore.load() else {
            throw SessionRefresherError.authExpired
        }
        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("auth/refresh")
        let body = try? JSONSerialization.data(withJSONObject: ["refreshToken": session.refreshToken])
        var request = TankbookHTTPRequest(url: url, method: "POST", body: body)
        request.headers["Content-Type"] = "application/json"

        let response: TankbookHTTPResponse
        do {
            response = try await client.send(request)
        } catch TankbookHTTPClientError.httpError {
            // The refresh token is dead - the server answered with a non-2xx.
            // Sign out locally - the chain is gone server-side and can never
            // be used again.
            try? sessionStore.clear()
            throw SessionRefresherError.authExpired
        } catch {
            throw SessionRefresherError.transportUnavailable
        }

        guard let pair = try? Self.decodeTokenPair(response.body) else {
            throw SessionRefresherError.transportUnavailable
        }
        try? sessionStore.save(session.rotated(accessToken: pair.accessToken,
                                               refreshToken: pair.refreshToken))
        return pair.accessToken
    }

    private struct TokenPairPayload: Decodable {
        let accessToken: String
        let refreshToken: String
    }

    private static func decodeTokenPair(_ data: Data?) throws -> (accessToken: String, refreshToken: String) {
        guard let data else { throw SessionRefresherError.transportUnavailable }
        let payload = try JSONDecoder().decode(TokenPairPayload.self, from: data)
        return (payload.accessToken, payload.refreshToken)
    }
}

/// Supplies no token, so the refresher's client never builds an `Authorization`
/// header for `/auth/refresh` (the refresh token is in the body). The allowlist
/// check still applies - the client refuses a non-allowlisted host before any
/// I/O, exactly as it does everywhere else.
private struct NilTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}
