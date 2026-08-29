import Foundation

/// Failures surfaced by the auth service (docs/API.md -> Auth -> "Failure
/// statuses"). Raw values are the machine codes the UI maps to a next step;
/// none of them carries a token, idToken or email (hard rule 12).
public enum AuthError: Error, Sendable, Equatable {
    /// The provider is not one the backend accepts (`400`, or refused locally
    /// before any request).
    case unsupportedProvider
    /// The server answered but the response could not be decoded as a session.
    case invalidResponse
    /// The identity token did not verify (`401`).
    case unauthorized
    /// A malformed body (`400`).
    case badRequest
    /// The host could not be reached. The UI must return the user to a working
    /// app, never to a wall (hard rule 1).
    case transportUnavailable
}

/// The client half of the auth contract (docs/API.md -> Auth). Injected so the
/// sign-in flow is testable without a reachable backend; the production
/// implementation is `RemoteAuthService`.
public protocol AuthService: Sendable {
    /// Exchanges a verified identity token for a session (`POST /auth/session`).
    /// Creates the account on first sight - there is no registration.
    func signIn(identity: ProviderIdentity) async throws -> AuthSession

    /// Rotates the token pair (`POST /auth/refresh`). `accountId`, `deviceId`
    /// and `provider` are unchanged (the refresh response carries only tokens).
    func refresh(_ session: AuthSession) async throws -> AuthSession

    /// Signs out this device (`DELETE /auth/session`). Local data stays local.
    func signOut(_ session: AuthSession) async throws
}

/// The backend-backed auth service. Each call goes through `TankbookHTTPClient`
/// so the host-bound Authorization rule (docs/SECURITY.md -> "the token is
/// bound to the host") is enforced by the client, not by this type: a request
/// to a non-allowlisted host is refused before any I/O and carries no token.
public struct RemoteAuthService: AuthService {
    /// The device descriptor sent with `POST /auth/session` (docs/API.md).
    public struct SessionDevice: Sendable, Equatable {
        public let name: String
        public let platform: String

        public init(name: String, platform: String) {
            self.name = name
            self.platform = platform
        }
    }

    private let client: TankbookHTTPClient
    private let director: ConfigTransportDirector
    private let device: SessionDevice

    /// Builds the service over an injected transport (testable without sockets;
    /// docs/TESTING.md). The token provider reads the current session's access
    /// token, so `DELETE /auth/session` carries the bearer automatically while
    /// a fresh sign-in (no session yet) carries none.
    public init(
        director: ConfigTransportDirector,
        transport: any TankbookHTTPTransport,
        sessionStore: any SessionStore,
        device: SessionDevice
    ) {
        self.client = TankbookHTTPClient(
            transport: transport,
            tokenProvider: SessionTokenProvider(sessionStore: sessionStore)
        )
        self.director = director
        self.device = device
    }

    public func signIn(identity: ProviderIdentity) async throws -> AuthSession {
        let body: [String: Any] = [
            "provider": identity.provider.rawValue,
            "idToken": identity.idToken,
            "device": ["name": device.name, "platform": device.platform],
        ]
        let response = try await post(path: "auth/session", body: body)
        guard (200...299).contains(response.status) else {
            throw Self.error(for: response.status)
        }
        return try Self.decodeSession(response.body, provider: identity.provider, email: identity.email)
    }

    public func refresh(_ session: AuthSession) async throws -> AuthSession {
        let body: [String: Any] = ["refreshToken": session.refreshToken]
        let response = try await post(path: "auth/refresh", body: body)
        guard (200...299).contains(response.status) else {
            throw Self.error(for: response.status)
        }
        let pair = try Self.decodeTokenPair(response.body)
        return session.rotated(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
    }

    public func signOut(_ session: AuthSession) async throws {
        let url = endpoint("auth/session")
        var request = TankbookHTTPRequest(url: url, method: "DELETE")
        request.headers["Authorization"] = "Bearer \(session.accessToken)"
        let response = try await send(request)
        guard (200...299).contains(response.status) || response.status == 204 else {
            throw Self.error(for: response.status)
        }
    }

    // MARK: - Requests

    private func post(path: String, body: [String: Any]) async throws -> TankbookHTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = TankbookHTTPRequest(url: endpoint(path), method: "POST", body: data)
        request.headers["Content-Type"] = "application/json"
        return try await send(request)
    }

    /// Sends a request and reports its outcome to the config layer
    /// (docs/CONFIG.md -> "Auto-revert on sustained failure"). A response of any
    /// status means the host answered; a thrown transport error means it did not.
    private func send(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        do {
            let response = try await client.send(request)
            await director.report(.response(status: response.status))
            return response
        } catch {
            await director.report(.transportFailure)
            throw error
        }
    }

    /// All auth endpoints live under `/v1` (docs/API.md -> "Ops" / backend
    /// `Program.cs`: `app.MapGroup("/v1")`).
    private func endpoint(_ path: String) -> URL {
        director.baseURL().appendingPathComponent("v1").appendingPathComponent(path)
    }

    private static func error(for status: Int) -> AuthError {
        switch status {
        case 401: return .unauthorized
        case 400: return .badRequest
        default: return .invalidResponse
        }
    }

    // MARK: - Decoding

    private struct SessionPayload: Decodable {
        let accessToken: String
        let refreshToken: String
        let accountId: String
        let deviceId: String
    }

    private struct TokenPairPayload: Decodable {
        let accessToken: String
        let refreshToken: String
    }

    private static func decodeSession(_ data: Data?, provider: AuthProvider, email: String?) throws -> AuthSession {
        guard let data else { throw AuthError.invalidResponse }
        let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
        return AuthSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            accountId: payload.accountId,
            deviceId: payload.deviceId,
            provider: provider,
            email: email
        )
    }

    private static func decodeTokenPair(_ data: Data?) throws -> (accessToken: String, refreshToken: String) {
        guard let data else { throw AuthError.invalidResponse }
        let payload = try JSONDecoder().decode(TokenPairPayload.self, from: data)
        return (payload.accessToken, payload.refreshToken)
    }
}

/// Supplies the current access token to `TankbookHTTPClient`. The client only
/// consults this **after** an allowlist check passes (docs/SECURITY.md), so the
/// token is never requested for a host the app must not talk to.
private struct SessionTokenProvider: AuthorizationTokenProvider {
    let sessionStore: any SessionStore

    func token() -> String? {
        try? sessionStore.load()?.accessToken
    }
}
