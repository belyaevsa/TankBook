import Foundation
import Testing
@testable import TankbookCore

// P4.4: the backend auth service (docs/API.md -> Auth). The client half posts
// the exact bodies the contract specifies and maps statuses; the host-bound
// Authorization rule is enforced by `TankbookHTTPClient`, so the off-allowlist
// test asserts the token is never even fetched for a foreign host.
@Suite("RemoteAuthService (P4.4)")
struct AuthServiceTests {

    private static let baseURL = URL(string: "https://api.tankbook.live")!

    private func makeService(transport: AuthRecordingTransport,
                             store: InMemorySessionStore) -> RemoteAuthService {
        RemoteAuthService(
            director: ConfigTransportDirector(baseURL: { Self.baseURL }, report: { _ in }),
            transport: transport,
            sessionStore: store,
            device: RemoteAuthService.SessionDevice(name: "iPhone 17 Pro", platform: "iOS")
        )
    }

    private func identity() -> ProviderIdentity {
        ProviderIdentity(provider: .apple, idToken: "id-token", email: "driver@icloud.com")
    }

    // MARK: - Sign in

    @Test func signInPostsTheSessionBodyAndReturnsTheParsedSession() async throws {
        let transport = AuthRecordingTransport()
        let service = makeService(transport: transport, store: InMemorySessionStore())
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"at","refreshToken":"rt","accountId":"acc","deviceId":"dev"}
                """.data(using: .utf8)!)
        ])

        let session = try await service.signIn(identity: identity())

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].method == "POST")
        #expect(sent[0].url.path == "/v1/auth/session")
        #expect(sent[0].headers["Authorization"] == nil, "a fresh sign-in carries no bearer")

        let body = try JSONSerialization.jsonObject(with: sent[0].body ?? Data()) as? [String: Any]
        #expect(body?["provider"] as? String == "apple")
        #expect(body?["idToken"] as? String == "id-token")
        let device = body?["device"] as? [String: Any]
        #expect(device?["name"] as? String == "iPhone 17 Pro")
        #expect(device?["platform"] as? String == "iOS")

        #expect(session.accessToken == "at")
        #expect(session.refreshToken == "rt")
        #expect(session.accountId == "acc")
        #expect(session.deviceId == "dev")
        #expect(session.provider == .apple)
    }

    @Test func signInWithARejectedTokenThrowsUnauthorized() async {
        let transport = AuthRecordingTransport()
        let service = makeService(transport: transport, store: InMemorySessionStore())
        transport.script([TankbookHTTPResponse(status: 401)])

        await #expect(throws: AuthError.unauthorized) {
            _ = try await service.signIn(identity: identity())
        }
    }

    // MARK: - The stored deviceId travels with the exchange (RV.41)

    @Test func signInSendsTheStoredDeviceIdWhenOneExists() async throws {
        let transport = AuthRecordingTransport()
        let stored = AuthSession(accessToken: "old-at", refreshToken: "old-rt",
                                 accountId: "acc", deviceId: "dev-123", provider: .apple)
        let service = makeService(transport: transport, store: InMemorySessionStore(session: stored))
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"at","refreshToken":"rt","accountId":"acc","deviceId":"dev-123"}
                """.data(using: .utf8)!)
        ])

        _ = try await service.signIn(identity: identity())

        let body = try JSONSerialization.jsonObject(with: transport.receivedRequests()[0].body ?? Data()) as? [String: Any]
        let device = body?["device"] as? [String: Any]
        #expect(device?["deviceId"] as? String == "dev-123",
                "a returning install sends its stored deviceId so the server reuses the row")
    }

    @Test func signInOmitsTheDeviceIdOnAFreshInstall() async throws {
        let transport = AuthRecordingTransport()
        let service = makeService(transport: transport, store: InMemorySessionStore())
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"at","refreshToken":"rt","accountId":"acc","deviceId":"dev"}
                """.data(using: .utf8)!)
        ])

        _ = try await service.signIn(identity: identity())

        let body = try JSONSerialization.jsonObject(with: transport.receivedRequests()[0].body ?? Data()) as? [String: Any]
        let device = body?["device"] as? [String: Any]
        #expect(device?["deviceId"] == nil,
                "a fresh install has no stored deviceId and sends none")
    }

    // MARK: - The account email prefers the server (RV.39)

    /// The regression is that the credential's email is nil on every re-sign-in,
    /// so a client that depends on it shows "Apple ID". The server value is the
    /// account's stored email and survives every sign-in. Assert equality, not
    /// non-emptiness - "Apple ID" is non-empty and is the bug.
    @Test func signInPrefersTheServerEmailOverANilCredential() async throws {
        let transport = AuthRecordingTransport()
        let service = makeService(transport: transport, store: InMemorySessionStore())
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"at","refreshToken":"rt","accountId":"acc","deviceId":"dev","email":"driver@icloud.com"}
                """.data(using: .utf8)!)
        ])

        let session = try await service.signIn(identity: ProviderIdentity(provider: .apple, idToken: "id", email: nil))

        #expect(session.email == "driver@icloud.com")
    }

    @Test func signInFallsBackToTheCredentialEmailWhenTheServerHasNone() async throws {
        let transport = AuthRecordingTransport()
        let service = makeService(transport: transport, store: InMemorySessionStore())
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"at","refreshToken":"rt","accountId":"acc","deviceId":"dev"}
                """.data(using: .utf8)!)
        ])

        let session = try await service.signIn(identity: ProviderIdentity(provider: .apple, idToken: "id", email: "first@icloud.com"))

        #expect(session.email == "first@icloud.com",
                "a first-run credential email is a bonus, kept when the server has none")
    }

    @Test func signInLeavesEmailNilWhenNeitherTheServerNorTheCredentialHasOne() async throws {
        let transport = AuthRecordingTransport()
        let service = makeService(transport: transport, store: InMemorySessionStore())
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"at","refreshToken":"rt","accountId":"acc","deviceId":"dev"}
                """.data(using: .utf8)!)
        ])

        let session = try await service.signIn(identity: ProviderIdentity(provider: .apple, idToken: "id", email: nil))

        #expect(session.email == nil,
                "a genuine no-email account keeps nil so the UI renders the provider name")
    }

    // MARK: - Refresh

    @Test func refreshRotatesTokensAndKeepsAccountAndDevice() async throws {
        let transport = AuthRecordingTransport()
        let existing = AuthSession(
            accessToken: "old-at", refreshToken: "old-rt",
            accountId: "acc", deviceId: "dev", provider: .google)
        let service = makeService(transport: transport, store: InMemorySessionStore(session: existing))
        transport.script([
            TankbookHTTPResponse(status: 200, body: """
                {"accessToken":"new-at","refreshToken":"new-rt"}
                """.data(using: .utf8)!)
        ])

        let refreshed = try await service.refresh(existing)

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].method == "POST")
        #expect(sent[0].url.path == "/v1/auth/refresh")
        let body = try JSONSerialization.jsonObject(with: sent[0].body ?? Data()) as? [String: Any]
        #expect(body?["refreshToken"] as? String == "old-rt")

        #expect(refreshed.accessToken == "new-at")
        #expect(refreshed.refreshToken == "new-rt")
        #expect(refreshed.accountId == "acc")
        #expect(refreshed.deviceId == "dev")
        #expect(refreshed.provider == .google)
    }

    // MARK: - Sign out

    @Test func signOutDeletesWithTheBearerFromTheStoredSession() async throws {
        let transport = AuthRecordingTransport()
        let session = AuthSession(
            accessToken: "at", refreshToken: "rt",
            accountId: "acc", deviceId: "dev", provider: .apple)
        let service = makeService(transport: transport, store: InMemorySessionStore(session: session))
        transport.script([TankbookHTTPResponse(status: 204)])

        try await service.signOut(session)

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].method == "DELETE")
        #expect(sent[0].url.path == "/v1/auth/session")
        #expect(sent[0].headers["Authorization"] == "Bearer at")
    }

    // MARK: - The host-bound token (docs/SECURITY.md)

    /// A sign-in to a non-allowlisted host is refused before any I/O and before
    /// the session token is even fetched - the guardrail that survives a
    /// redirected `apiBaseUrl` (docs/SECURITY.md -> "the token is bound to the
    /// host, not to the session").
    @Test func aNonAllowlistedBaseURLIsRefusedWithoutFetchingTheToken() async {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: AuthSession(
            accessToken: "secret", refreshToken: "rt",
            accountId: "acc", deviceId: "dev", provider: .apple))
        let service = RemoteAuthService(
            director: ConfigTransportDirector(baseURL: { URL(string: "https://evil.com")! }, report: { _ in }),
            transport: transport,
            sessionStore: store,
            device: RemoteAuthService.SessionDevice(name: "iPhone 17 Pro", platform: "iOS")
        )

        await #expect(throws: TankbookHTTPClientError.hostNotAllowlisted) {
            _ = try await service.signIn(identity: identity())
        }

        #expect(transport.receivedRequests().isEmpty, "a non-allowlisted host must not reach I/O")
        #expect(store.loadCount == 0, "the session token must never be fetched for a non-allowlisted host")
    }
}
