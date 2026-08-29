import Foundation
import Testing
@testable import TankbookCore

// PR.1 - the shared token refresher (docs/PRACTICES.md S7). The load-bearing
// invariant is single-flight: the server rotates refresh tokens and revokes the
// chain on reuse, so two racing refreshes sign the user out. A 401 storm from
// many transport owners must collapse to ONE `POST /auth/refresh`.

private struct StaleTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { "old-at" }
}

private func makeSession(accessToken: String = "old-at",
                         refreshToken: String = "old-rt") -> AuthSession {
    AuthSession(accessToken: accessToken, refreshToken: refreshToken,
                accountId: "acc", deviceId: "dev", provider: .apple)
}

private func refreshPairBody(_ access: String = "new-at", _ refresh: String = "new-rt") -> Data {
    Data("""
    {"accessToken":"\(access)","refreshToken":"\(refresh)"}
    """.utf8)
}

@Suite("SessionRefresher (PR.1)")
struct SessionRefresherTests {

    private static let baseURL = URL(string: "https://api.tankbook.live")!

    private func makeRefresher(transport: AuthRecordingTransport,
                               store: InMemorySessionStore) -> SessionRefresher {
        SessionRefresher(baseURL: Self.baseURL, transport: transport, sessionStore: store)
    }

    // MARK: - Single flight

    /// The load-bearing test: two concurrent refreshes must produce ONE
    /// `POST /auth/refresh`. Written to genuinely race - two `async let` calls
    /// awaiting the same actor - not two sequential awaits.
    @Test func twoConcurrentRefreshesProduceOneRefresh() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: makeSession())
        let refresher = makeRefresher(transport: transport, store: store)
        transport.script([TankbookHTTPResponse(status: 200, body: refreshPairBody())])

        async let first: String = refresher.refresh()
        async let second: String = refresher.refresh()
        let (firstToken, secondToken) = try await (first, second)

        #expect(firstToken == "new-at")
        #expect(secondToken == "new-at")

        let refreshes = transport.receivedRequests().filter { $0.url.path == "/v1/auth/refresh" }
        #expect(refreshes.count == 1, "concurrent 401s must share one in-flight refresh, not start two")
    }

    // MARK: - Success

    @Test func aRefreshPersistsTheRotatedPairAndReturnsTheNewToken() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: makeSession())
        let refresher = makeRefresher(transport: transport, store: store)
        transport.script([TankbookHTTPResponse(status: 200, body: refreshPairBody())])

        let token = try await refresher.refresh()

        #expect(token == "new-at")

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].method == "POST")
        #expect(sent[0].url.path == "/v1/auth/refresh")
        let body = try JSONSerialization.jsonObject(with: sent[0].body ?? Data()) as? [String: Any]
        #expect(body?["refreshToken"] as? String == "old-rt")

        let persisted = try store.load()
        #expect(persisted?.accessToken == "new-at")
        #expect(persisted?.refreshToken == "new-rt")
        #expect(persisted?.accountId == "acc", "the rotated pair keeps account and device")
        #expect(persisted?.deviceId == "dev")
    }

    // MARK: - Failure

    @Test func aRefreshThat401sClearsTheSessionAndYieldsAuthExpired() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: makeSession())
        let refresher = makeRefresher(transport: transport, store: store)
        transport.script([TankbookHTTPResponse(status: 401)])

        await #expect(throws: SessionRefresherError.authExpired) {
            _ = try await refresher.refresh()
        }
        #expect(try store.load() == nil, "a rejected refresh token must sign the user out locally")
    }

    @Test func aRefreshWithNoSessionYieldsAuthExpired() async {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: nil)
        let refresher = makeRefresher(transport: transport, store: store)

        await #expect(throws: SessionRefresherError.authExpired) {
            _ = try await refresher.refresh()
        }
        #expect(transport.receivedRequests().isEmpty, "no session means no refresh request")
    }

    @Test func aTransportFailureYieldsTransportUnavailableAndKeepsTheSession() async throws {
        let transport = AuthRecordingTransport()
        transport.failAllRequests()
        let store = InMemorySessionStore(session: makeSession())
        let refresher = makeRefresher(transport: transport, store: store)

        await #expect(throws: SessionRefresherError.transportUnavailable) {
            _ = try await refresher.refresh()
        }
        #expect(try store.load()?.accessToken == "old-at",
                "an unreachable server must NOT sign the user out")
    }

    // MARK: - The client intercepts 401 and replays with the new bearer

    @Test func a401RefreshesOnceAndReplaysTheRequestWithTheNewBearer() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: makeSession())
        let refresher = makeRefresher(transport: transport, store: store)
        // The stale provider still returns the OLD token - the replay must carry
        // the ROTATED bearer, never re-read from a provider that has not caught up.
        let client = TankbookHTTPClient(transport: transport,
                                        tokenProvider: StaleTokenProvider(),
                                        refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 200, body: refreshPairBody()),
            TankbookHTTPResponse(status: 200, body: Data("ok".utf8))
        ])

        let url = URL(string: "https://api.tankbook.live/v1/sync/pull")!
        let response = try await client.send(TankbookHTTPRequest(url: url))

        #expect(response.status == 200)

        let sent = transport.receivedRequests()
        #expect(sent.count == 3, "original, refresh, replay")
        #expect(sent[0].headers["Authorization"] == "Bearer old-at")
        #expect(sent[1].url.path == "/v1/auth/refresh")
        #expect(sent[2].url.path == "/v1/sync/pull")
        #expect(sent[2].headers["Authorization"] == "Bearer new-at",
                "the replay must carry the rotated bearer, not the stale one")
    }
}
