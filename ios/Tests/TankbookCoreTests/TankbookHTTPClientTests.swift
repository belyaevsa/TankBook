import Foundation
import os
import Testing
@testable import TankbookCore

// P0.12c: the host-bound HTTP client (docs/SECURITY.md -> "Defence in depth").
// The client is the second, independent checkpoint: config validation and this
// client enforce the same allowlist, so the tests drive the client directly
// with a non-allowlisted URL (never through config validation) and assert on
// what the client *constructed* - the transport double records the exact
// request it was handed and the token provider records whether it was consulted.

// MARK: - Doubles

private final class RecordingTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var responses: [TankbookHTTPResponse] = []
        var received: [TankbookHTTPRequest] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0.responses = responses }
    }

    func receivedRequests() -> [TankbookHTTPRequest] {
        lock.withLock { $0.received }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { state in
            state.received.append(request)
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200) }
            return state.responses.removeFirst()
        }
    }
}

private final class RecordingTokenProvider: AuthorizationTokenProvider, @unchecked Sendable {
    private struct State {
        var calls = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let tokenValue: String?

    init(token: String?) { self.tokenValue = token }

    func token() -> String? {
        lock.withLock { $0.calls += 1 }
        return tokenValue
    }

    func callCount() -> Int {
        lock.withLock { $0.calls }
    }
}

/// A refresher that returns a fixed bearer without a round trip - the seam for
/// deciding "the token did not change" (RV.65). The real refresher always
/// rotates or throws; a stub that hands back the SAME token is exactly the
/// dead-session shape the production log showed (no `/auth/refresh` line, the
/// replay re-sending the image against the same rejected bearer).
private struct FixedTokenRefresher: SessionRefreshing {
    let token: String

    func refresh() async throws -> String {
        token
    }
}

@Suite("TankbookHTTPClient (P0.12c)")
struct TankbookHTTPClientTests {

    /// A pinned app identity so the header assertions are exact even in a
    /// `swift test` process with no Info.plist (PR.8).
    private static let appInfo = TankbookAppInfo(
        version: AppVersion(major: 1, minor: 0, patch: 0), build: "1", platform: "ios", schemaVersion: 1)

    private static func makeClient(transport: RecordingTransport, token: String? = nil) -> TankbookHTTPClient {
        TankbookHTTPClient(transport: transport,
                           tokenProvider: RecordingTokenProvider(token: token),
                           appInfo: appInfo)
    }

    // MARK: Checkpoint two: request-time allowlist

    @Test func nonAllowlistedHostIsRefusedBeforeAnyIOAndNoTokenIsFetched() async {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "secret-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        await #expect(throws: TankbookHTTPClientError.hostNotAllowlisted) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://evil.com/")!))
        }

        #expect(transport.receivedRequests().isEmpty, "a non-allowlisted host must not reach I/O")
        #expect(provider.callCount() == 0, "the token must never be requested for a non-allowlisted host")
    }

    @Test func allowlistedHostGetsAuthorizationAndIsSent() async throws {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "test-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        let url = URL(string: "https://api.tankbook.live/health")!
        _ = try await client.send(TankbookHTTPRequest(url: url))

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].url == url)
        #expect(sent[0].headers["Authorization"] == "Bearer test-token")
        #expect(provider.callCount() == 1)
    }

    @Test func redirectToAnAllowlistedHostRechecksAndKeepsTheToken() async throws {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "test-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        transport.script([
            TankbookHTTPResponse(status: 302, headers: ["Location": "https://eu.api.tankbook.live/x"]),
            TankbookHTTPResponse(status: 200),
        ])

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 2)
        #expect(sent[0].headers["Authorization"] == "Bearer test-token")
        #expect(sent[1].url.absoluteString == "https://eu.api.tankbook.live/x")
        #expect(sent[1].headers["Authorization"] == "Bearer test-token", "an allowlisted hop re-attaches the token")
    }

    @Test func redirectToANonAllowlistedHostDropsAuthorization() async throws {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "test-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        transport.script([
            TankbookHTTPResponse(status: 302, headers: ["Location": "https://evil.com/steal"]),
            TankbookHTTPResponse(status: 200),
        ])

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 2, "the redirect is followed, just unauthenticated")
        #expect(sent[0].headers["Authorization"] == "Bearer test-token")
        #expect(sent[1].url.absoluteString == "https://evil.com/steal")
        #expect(sent[1].headers["Authorization"] == nil, "a non-allowlisted redirect target must not carry the token")
        #expect(provider.callCount() == 1, "the token is fetched once, for the allowlisted hop only")
    }

    @Test func redirectToAForeignHostPreservesASuppliedHeaderButNeverAuthorization() async throws {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "test-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        transport.script([
            TankbookHTTPResponse(status: 301, headers: ["Location": "https://evil.com/steal"]),
            TankbookHTTPResponse(status: 200),
        ])

        var request = TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/")!)
        request.headers["X-Custom"] = "kept"
        _ = try await client.send(request)

        let sent = transport.receivedRequests()
        #expect(sent[1].headers["X-Custom"] == "kept")
        #expect(sent[1].headers["Authorization"] == nil)
    }

    @Test func redirectLoopIsBounded() async {
        let transport = RecordingTransport()
        let client = TankbookHTTPClient(
            transport: transport,
            tokenProvider: RecordingTokenProvider(token: "test-token"),
            maxRedirects: 3
        )
        transport.script(Array(repeating: TankbookHTTPResponse(
            status: 302, headers: ["Location": "https://api.tankbook.live/again"]
        ), count: 10))

        await #expect(throws: TankbookHTTPClientError.tooManyRedirects) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/")!))
        }
    }

    @Test func aUserinfoAuthorityIsRefusedAsItsRealHost() async {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "secret-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        await #expect(throws: TankbookHTTPClientError.hostNotAllowlisted) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live@evil.com/")!))
        }
        #expect(provider.callCount() == 0)
        #expect(transport.receivedRequests().isEmpty)
    }

    @Test func aMissingTokenStillSendsForAnAllowlistedHost() async throws {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: nil)
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].headers["Authorization"] == nil, "no token means no Authorization header")
    }

    // MARK: PR.8 - trace and app headers on the wire

    @Test func everyRequestCarriesATraceHeaderAndTheAppHeaders() async throws {
        let transport = RecordingTransport()
        let client = Self.makeClient(transport: transport)

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/config")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        let headers = sent[0].headers
        #expect(headers["X-Tankbook-Trace"] != nil)
        #expect(headers["X-Tankbook-App"] == "1.0.0+1")
        #expect(headers["X-Tankbook-Platform"] == "ios")
        #expect(headers["X-Tankbook-Schema-Version"] == "1")
    }

    /// The vacuous trap the brief names: asserting the header exists without
    /// asserting it is UNIQUE per call. A constant trace id passes an existence
    /// check and is useless in support.
    @Test func theTraceIdIsUniquePerCallAndIsAUUIDv7() async throws {
        let transport = RecordingTransport()
        let client = Self.makeClient(transport: transport)

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/one")!))
        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/two")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 2)
        let first = sent[0].headers["X-Tankbook-Trace"]
        let second = sent[1].headers["X-Tankbook-Trace"]
        #expect(UUID(uuidString: first!) != nil, "the trace id must be a UUID")
        #expect(first!.dropFirst(14).first == "7", "the trace id must be a UUIDv7 (version nibble 7)")
        #expect(first != second, "two calls must never share a trace id - that is the point of it")
    }

    /// Redirect hops and a 401 replay are ONE logical request, so they keep the
    /// caller's trace id rather than minting a fresh one per hop.
    @Test func aRedirectCarriesTheSameTraceIdToTheNextHop() async throws {
        let transport = RecordingTransport()
        transport.script([
            TankbookHTTPResponse(status: 302, headers: ["Location": "https://eu.api.tankbook.live/x"]),
            TankbookHTTPResponse(status: 200)
        ])
        let client = Self.makeClient(transport: transport)

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 2)
        #expect(sent[0].headers["X-Tankbook-Trace"] == sent[1].headers["X-Tankbook-Trace"],
                "a redirect is the same request, so support must see one trace id")
    }

    @Test func aNon2xxThrowsAnErrorCarryingTheTraceIdFromTheBody() async throws {
        let transport = RecordingTransport()
        transport.script([
            TankbookHTTPResponse(status: 422,
                                 body: Data(#"{"traceId":"9f3a5b1e-cd42-4f09-9a2b-1c2d3e4f5a6b"}"#.utf8))
        ])
        let client = Self.makeClient(transport: transport)

        await #expect(throws: TankbookHTTPClientError.httpError(
            status: 422,
            traceId: "9f3a5b1e-cd42-4f09-9a2b-1c2d3e4f5a6b",
            retryAfterSeconds: nil
        )) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/x")!))
        }
    }

    @Test func a5xxThrowsAnErrorEvenWithoutATraceIdInTheBody() async throws {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 500, body: Data("{}".utf8))])
        let client = Self.makeClient(transport: transport)

        await #expect(throws: TankbookHTTPClientError.httpError(
            status: 500, traceId: nil, retryAfterSeconds: nil
        )) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/x")!))
        }
    }

    @Test func a429CarriesTheServersRetryAfterOnTheError() async throws {
        let transport = RecordingTransport()
        transport.script([
            TankbookHTTPResponse(status: 429, headers: ["Retry-After": "120"],
                                 body: Data(#"{"traceId":"trace-abc"}"#.utf8))
        ])
        let client = Self.makeClient(transport: transport)

        await #expect(throws: TankbookHTTPClientError.httpError(
            status: 429, traceId: "trace-abc", retryAfterSeconds: 120
        )) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/x")!))
        }
    }

    /// A 304 "not modified" is a legitimate outcome for config/catalog fetches
    /// and must pass through, not throw (the client throws on non-2xx EXCEPT 304).
    @Test func a304NotModifiedIsReturnedNotThrown() async throws {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 304)])
        let client = Self.makeClient(transport: transport)

        let response = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/x")!))
        #expect(response.status == 304)
    }

    // MARK: RV.65 - the 401 replay sends a large body only when the token changed

    /// The headline L1: a 401 whose refresh hands back the SAME bearer must NOT
    /// replay the request. The production defect was re-sending a 53 KB image
    /// against a token the server had already rejected - bytes sent for
    /// nothing. This asserts the request COUNT **and** the total bytes the
    /// transport received: "the call failed" passes against this bug, and one
    /// request with a tiny body hides the cost the row exists to remove.
    @Test func a401WithAnUnchangedTokenDoesNotReplayTheBody() async throws {
        let transport = RecordingTransport()
        // The refresher returns the very token the request already carried:
        // nothing changed, so there is nothing to retry.
        let refresher = FixedTokenRefresher(token: "test-token")
        let client = TankbookHTTPClient(
            transport: transport,
            tokenProvider: RecordingTokenProvider(token: "test-token"),
            refresher: refresher)

        // A realistic rendition-sized body, not a toy: the whole point of the
        // row is that the bytes are large enough to matter.
        let body = Data(repeating: 0xAB, count: 53_457)
        transport.script([TankbookHTTPResponse(status: 401)])

        var request = TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/v1/extract")!,
                                          method: "POST", body: body)
        request.headers["Content-Type"] = "application/json"

        await #expect(throws: TankbookHTTPClientError.httpError(
            status: 401, traceId: nil, retryAfterSeconds: nil)) {
            _ = try await client.send(request)
        }

        let sent = transport.receivedRequests()
        #expect(sent.count == 1,
                "an unchanged token means nothing to retry - the body must go out ONCE")
        let totalBytes = sent.reduce(0) { $0 + ($1.body?.count ?? 0) }
        #expect(totalBytes == body.count,
                "exactly one body's bytes must be sent, never two (RV.65: 855 KB for nothing)")
    }

    /// A genuine rotation still replays exactly once - the 401 refresh-and-retry
    /// is load-bearing when the token really changed (RV.65: the defect was the
    /// UNCHANGED case, never rotation).
    @Test func a401WithARotatedTokenReplaysTheBodyOnceAndSucceeds() async throws {
        let transport = RecordingTransport()
        let refresher = FixedTokenRefresher(token: "rotated-token")
        let client = TankbookHTTPClient(
            transport: transport,
            tokenProvider: RecordingTokenProvider(token: "test-token"),
            refresher: refresher)

        let body = Data(repeating: 0xAB, count: 53_457)
        transport.script([
            TankbookHTTPResponse(status: 401),
            TankbookHTTPResponse(status: 200, body: Data("ok".utf8))
        ])

        var request = TankbookHTTPRequest(url: URL(string: "https://api.tankbook.live/v1/extract")!,
                                          method: "POST", body: body)
        request.headers["Content-Type"] = "application/json"
        let response = try await client.send(request)

        #expect(response.status == 200)
        let sent = transport.receivedRequests()
        #expect(sent.count == 2, "a genuine rotation replays exactly once")
        let totalBytes = sent.reduce(0) { $0 + ($1.body?.count ?? 0) }
        #expect(totalBytes == body.count * 2,
                "rotation replays the body once: two bodies total, never three")
        #expect(sent[1].headers["Authorization"] == "Bearer rotated-token",
                "the replay must carry the rotated bearer, never the stale one")
    }

    /// The trace id is generated only after the allowlist check, so a refused
    /// host neither mints one nor builds any header (same posture as the token).
    @Test func aRefusedHostDoesNotMintATraceIdOrTouchTheTransport() async {
        let transport = RecordingTransport()
        let client = Self.makeClient(transport: transport)

        await #expect(throws: TankbookHTTPClientError.hostNotAllowlisted) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://evil.com/")!))
        }
        #expect(transport.receivedRequests().isEmpty)
    }
}
