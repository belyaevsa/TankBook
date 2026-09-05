import Foundation
import Testing
@testable import TankbookCore

// RV.26 - the gateway must be armed only when the session can actually
// authenticate. The defect was arming at all: `GatewayScanStarter.makeTransport`
// gated on `load() != nil`, so a session that merely existed (but whose refresh
// had been rejected) still uploaded the image for a guaranteed 401. The fix
// wires the SAME single-flight refresher the sync path uses into the gateway
// transport, and treats a rejected refresh as an auth event, never a transient
// failure to retry.
//
// These tests count the requests the transport actually made - asserting
// "the call failed" passes against the bug, which is exactly why the counts
// are the assertion (the trap named in the RV.26 brief).

@Suite("Gateway auth (RV.26)")
struct GatewayAuthTests {

    private static let baseURL = URL(string: "https://api.tankbook.live")!

    private static func director() -> ConfigTransportDirector {
        ConfigTransportDirector(baseURL: { baseURL }, report: { _ in })
    }

    private static func makeSession(accessToken: String = "old-at",
                                    refreshToken: String = "old-rt") -> AuthSession {
        AuthSession(accessToken: accessToken, refreshToken: refreshToken,
                    accountId: "acc", deviceId: "dev", provider: .apple)
    }

    private static func refreshPairBody(_ access: String = "new-at",
                                        _ refresh: String = "new-rt") -> Data {
        Data("""
        {"accessToken":"\(access)","refreshToken":"\(refresh)"}
        """.utf8)
    }

    private static func extractionBody() -> Data {
        Data(#"{"fields":{"total":{"value":71.02,"confidence":0.9}},"pipeline":"p"}"#.utf8)
    }

    private static func request() -> GatewayExtractRequest {
        .init(kind: "receipt", imageJPEG: Data("jpeg-bytes".utf8))
    }

    /// A request with a realistic rendition body (RV.65): the defect is the
    /// payload's size, so a toy body hides the exact cost the row removes.
    private static func request(renditionBytes: Int) -> GatewayExtractRequest {
        .init(kind: "receipt", imageJPEG: Data(repeating: 0xAB, count: renditionBytes))
    }

    private struct StaleTokenProvider: AuthorizationTokenProvider {
        func token() -> String? { "old-at" }
    }

    /// A refresher stub returning a fixed bearer without a round trip - the
    /// seam for RV.65's "unchanged" / "rotated" cases. The real refresher
    /// always rotates or throws; the stub makes the token comparison the thing
    /// under test.
    private struct StaticRefresher: SessionRefreshing {
        let token: String

        func refresh() async throws -> String {
            token
        }
    }

    /// The stale-token case (the production log): a session whose access token
    /// has aged out but whose refresh token is still valid. The gateway must
    /// refresh on the 401 and replay once, exactly as sync does - and the
    /// replay must carry the rotated bearer, never the stale one.
    @Test func aStaleSessionRefreshesOn401AndReplaysOnce() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: Self.makeSession())
        let refresher = SessionRefresher(baseURLProvider: { Self.baseURL },
                                         transport: transport,
                                         sessionStore: store)
        let client = RemoteGatewayExtractTransport(
            director: Self.director(),
            transport: transport,
            tokenProvider: StaleTokenProvider(),
            refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 200, body: Self.refreshPairBody()),
            TankbookHTTPResponse(status: 200, body: Self.extractionBody())
        ])

        let extraction = try await client.extract(Self.request())

        #expect(extraction.total?.value == Decimal(string: "71.02"))

        let sent = transport.receivedRequests()
        let extracts = sent.filter { $0.url.path == "/v1/extract" }
        let refreshes = sent.filter { $0.url.path == "/v1/auth/refresh" }
        #expect(extracts.count == 2, "a stale session produces one retried extract request, no more")
        #expect(refreshes.count == 1, "exactly one refresh, shared single-flight")
        #expect(extracts.last?.headers["Authorization"] == "Bearer new-at",
                "the replay carries the rotated bearer, never the stale one")
    }

    // MARK: - RV.65 a dead session must not re-upload the image

    /// The headline L1 (the production log's exact shape): a 401 whose refresh
    /// returns an UNCHANGED bearer. There is nothing to retry - the server
    /// already rejected exactly this token - so the image goes out ONCE, not
    /// twice, and the refusal surfaces as an auth event the surface can name.
    /// The assertion is the request COUNT and the BYTES the transport received
    /// (a realistic rendition, not a toy body), because "the call failed"
    /// passes against the pre-fix double upload.
    @Test func anUnchangedToken401SendsTheImageOnceAndSurfacesAuthExpired() async throws {
        let transport = AuthRecordingTransport()
        // A refresher that hands back the SAME bearer - the shape the production
        // log shows (no /auth/refresh line between the pairs): no rotation, so
        // replaying is re-sending the image against the same rejected token.
        let refresher = StaticRefresher(token: "old-at")
        let client = RemoteGatewayExtractTransport(
            director: Self.director(),
            transport: transport,
            tokenProvider: StaleTokenProvider(),
            refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 200, body: Self.extractionBody())
        ])

        let request = Self.request(renditionBytes: 40_000)
        await #expect(throws: SyncServerError.authExpired) {
            _ = try await client.extract(request)
        }

        let sent = transport.receivedRequests()
        let extracts = sent.filter { $0.url.path == "/v1/extract" }
        #expect(extracts.count == 1,
                "an unchanged token means nothing to retry - exactly ONE extract request")
        let bytes = extracts.reduce(0) { $0 + ($1.body?.count ?? 0) }
        #expect(bytes > 50_000,
                "the rendition must be realistically sized so the byte saving is the thing asserted")
        #expect(bytes < 2 * 53_457 + 1_000,
                "the image must be uploaded once: total extract bytes stay near one rendition")
    }

    /// The genuine-rotation case still replays once (the load-bearing
    /// refresh-and-retry), and a replay that is STILL refused is an auth event,
    /// never a silent "gate this client does not know" (PR.1).
    @Test func aRotationThatIsStillRefusedSurfacesAuthExpiredAfterOneReplay() async throws {
        let transport = AuthRecordingTransport()
        // Rotation happens (new-at != old-at), so the one replay is legitimate;
        // the server still refuses, which is an auth event the surface names.
        let refresher = StaticRefresher(token: "new-at")
        let client = RemoteGatewayExtractTransport(
            director: Self.director(),
            transport: transport,
            tokenProvider: StaleTokenProvider(),
            refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 401)
        ])

        await #expect(throws: SyncServerError.authExpired) {
            _ = try await client.extract(Self.request())
        }
        let extracts = transport.receivedRequests().filter { $0.url.path == "/v1/extract" }
        #expect(extracts.count == 2, "a genuine rotation replays exactly once, never twice")
        #expect(extracts.last?.headers["Authorization"] == "Bearer new-at")
    }

    /// The dead-token case: the 401 is real and the refresh is rejected. The
    /// gateway must NOT retry (zero further extract requests) and must leave
    /// the session marked authExpired, so the surface can name "sign in again".
    @Test func aDeadSessionMarksAuthExpiredAndMakesNoFurtherExtractRequest() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: Self.makeSession())
        let refresher = SessionRefresher(baseURLProvider: { Self.baseURL },
                                         transport: transport,
                                         sessionStore: store)
        let client = RemoteGatewayExtractTransport(
            director: Self.director(),
            transport: transport,
            tokenProvider: StaleTokenProvider(),
            refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 401)
        ])

        await #expect(throws: SyncServerError.authExpired) {
            _ = try await client.extract(Self.request())
        }

        let sent = transport.receivedRequests()
        let extracts = sent.filter { $0.url.path == "/v1/extract" }
        let refreshes = sent.filter { $0.url.path == "/v1/auth/refresh" }
        #expect(extracts.count == 1, "a dead session makes zero FURTHER extract requests - never retried")
        #expect(refreshes.count == 1)
        #expect(try store.load() == nil, "the rejected refresh signs the user out locally")
        #expect(try store.isAuthExpired() == true, "the session is left marked authExpired")
    }

    /// A refused refresh must never be retried as if it were a transient
    /// failure: `authExpired` is not `transportUnavailable`, so the one silent
    /// retry in `extract` must not fire.
    @Test func anAuthExpiredOutcomeIsNotRetriedAsTransient() async throws {
        let transport = AuthRecordingTransport()
        let store = InMemorySessionStore(session: Self.makeSession())
        let refresher = SessionRefresher(baseURLProvider: { Self.baseURL },
                                         transport: transport,
                                         sessionStore: store)
        let client = RemoteGatewayExtractTransport(
            director: Self.director(),
            transport: transport,
            tokenProvider: StaleTokenProvider(),
            refresher: refresher)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 200, body: Self.extractionBody())
        ])

        await #expect(throws: SyncServerError.authExpired) {
            _ = try await client.extract(Self.request())
        }
        let extracts = transport.receivedRequests().filter { $0.url.path == "/v1/extract" }
        #expect(extracts.count == 1, "authExpired must surface, never be swallowed by a retry")
    }

    // MARK: - The arming gate (the row's zero-request invariant)

    /// The whole point of RV.26: a session that EXISTS but cannot authenticate
    /// (marked authExpired) must not arm the gateway - arming it is what
    /// uploaded the image for a guaranteed 401. A fresh session arms; a guest
    /// (no session) does not. The three fixtures together prove the gate is
    /// the mark, not the mere absence of a session.
    @Test func theArmingGateRequiresAnAuthenticableSession() throws {
        let marked = InMemorySessionStore(session: Self.makeSession())
        try marked.setAuthExpired(true)
        #expect(!GatewayArming.shouldArm(sessionStore: marked),
                "a session that exists but is marked auth-expired must NOT arm")

        let fresh = InMemorySessionStore(session: Self.makeSession())
        #expect(GatewayArming.shouldArm(sessionStore: fresh),
                "a fresh session arms the gateway")

        let guest = InMemorySessionStore(session: nil)
        #expect(!GatewayArming.shouldArm(sessionStore: guest),
                "a guest has no session and gets no gateway")
    }
}
