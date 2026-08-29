import Foundation
import Testing
@testable import TankbookCore

// PR.2 - sign-out revokes server-side and always clears locally (docs/SECURITY.md
// -> the sign-out test). A handed-over phone must never keep a 90-day refresh
// chain valid because the revoke request failed.

@Suite("SessionSignOut (PR.2)")
struct SessionSignOutTests {

    private static let baseURL = URL(string: "https://api.tankbook.live")!

    private func makeSignOut(transport: AuthRecordingTransport,
                             store: InMemorySessionStore) -> SessionSignOut {
        let service = RemoteAuthService(
            director: ConfigTransportDirector(baseURL: { Self.baseURL }, report: { _ in }),
            transport: transport,
            sessionStore: store,
            device: RemoteAuthService.SessionDevice(name: "iPhone 17 Pro", platform: "iOS")
        )
        return SessionSignOut(authService: service, sessionStore: store)
    }

    private func session() -> AuthSession {
        AuthSession(accessToken: "at", refreshToken: "rt",
                    accountId: "acc", deviceId: "dev", provider: .apple)
    }

    @Test func signOutIssuesTheDeleteAndClearsTheKeychainOn204() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: session())
        let signOut = makeSignOut(transport: transport, store: store)
        transport.script([TankbookHTTPResponse(status: 204)])

        await signOut.signOut()

        let sent = transport.receivedRequests()
        #expect(sent.count == 1, "sign-out must issue the server-side revoke")
        #expect(sent[0].method == "DELETE")
        #expect(sent[0].url.path == "/v1/auth/session")
        #expect(sent[0].headers["Authorization"] == "Bearer at")
        #expect(try store.load() == nil, "the Keychain is cleared on a successful sign-out")
    }

    @Test func signOutClearsTheKeychainWhenTheDeleteFails() async throws {
        let transport = AuthRecordingTransport()
        transport.failAllRequests()
        let store = InMemorySessionStore(session: session())
        let signOut = makeSignOut(transport: transport, store: store)

        await signOut.signOut()

        #expect(try store.load() == nil,
                "an offline sign-out still signs out locally (hard rule 1)")
    }
}
