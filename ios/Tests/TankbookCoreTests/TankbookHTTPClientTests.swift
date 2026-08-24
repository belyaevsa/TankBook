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

@Suite("TankbookHTTPClient (P0.12c)")
struct TankbookHTTPClientTests {

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

        let url = URL(string: "https://api.tankbook.app/health")!
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
            TankbookHTTPResponse(status: 302, headers: ["Location": "https://eu.api.tankbook.app/x"]),
            TankbookHTTPResponse(status: 200),
        ])

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.app/")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 2)
        #expect(sent[0].headers["Authorization"] == "Bearer test-token")
        #expect(sent[1].url.absoluteString == "https://eu.api.tankbook.app/x")
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

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.app/")!))

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

        var request = TankbookHTTPRequest(url: URL(string: "https://api.tankbook.app/")!)
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
            status: 302, headers: ["Location": "https://api.tankbook.app/again"]
        ), count: 10))

        await #expect(throws: TankbookHTTPClientError.tooManyRedirects) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.app/")!))
        }
    }

    @Test func aUserinfoAuthorityIsRefusedAsItsRealHost() async {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: "secret-token")
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        await #expect(throws: TankbookHTTPClientError.hostNotAllowlisted) {
            _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.app@evil.com/")!))
        }
        #expect(provider.callCount() == 0)
        #expect(transport.receivedRequests().isEmpty)
    }

    @Test func aMissingTokenStillSendsForAnAllowlistedHost() async throws {
        let transport = RecordingTransport()
        let provider = RecordingTokenProvider(token: nil)
        let client = TankbookHTTPClient(transport: transport, tokenProvider: provider)

        _ = try await client.send(TankbookHTTPRequest(url: URL(string: "https://api.tankbook.app/")!))

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].headers["Authorization"] == nil, "no token means no Authorization header")
    }
}
