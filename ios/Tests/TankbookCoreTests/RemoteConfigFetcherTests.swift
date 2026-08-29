import Foundation
import os
import Testing
@testable import TankbookCore

// PR.3a: the real config fetcher over TankbookHTTPClient (docs/API.md ->
// GET /v1/config). The fetcher's whole job is the wire: send If-None-Match,
// honour 304, extract the verbatim document bytes and the signature, carry the
// ETag. Signature verification is the store's job, not the fetcher's, so these
// tests assert on what the fetcher *constructed* and *extracted*, with a
// recording transport and a nil token provider (config is public).

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

private struct NilTokenProvider: AuthorizationTokenProvider, Sendable {
    func token() -> String? { nil }
}

private func makeClient(transport: RecordingTransport) -> TankbookHTTPClient {
    TankbookHTTPClient(transport: transport, tokenProvider: NilTokenProvider())
}

private let defaultBaseURL = URL(string: "https://api.tankbook.live")!

private func makeFetcher(transport: RecordingTransport, baseURL: URL = defaultBaseURL) -> RemoteConfigFetcher {
    RemoteConfigFetcher(client: makeClient(transport: transport), baseURLProvider: { baseURL })
}

/// A config document with deliberately distinctive raw bytes: `9007199254740993`
/// exceeds Double's integer range and `1e3` is a non-canonical token, so either
/// would change if the fetcher round-tripped the document through a JSON object
/// instead of extracting it verbatim.
private let rawDocument = "{\"version\":7,\"big\":9007199254740993,\"exp\":1e3}"

private func envelope(document: String = rawDocument, signature: String = "c2lnbmF0dXJl", version: Int = 7) -> Data {
    Data("{\"document\":\(document),\"signature\":\"\(signature)\",\"version\":\(version)}".utf8)
}

@Suite("RemoteConfigFetcher (PR.3a)")
struct RemoteConfigFetcherTests {

    @Test func fetchSendsIfNoneMatchWhenAnEtagIsKnown() async throws {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 200, headers: ["ETag": "\"7:abc\""], body: envelope())])
        let fetcher = makeFetcher(transport: transport)

        _ = try await fetcher.fetch(ifNoneMatch: "\"7:abc\"")

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].headers["If-None-Match"] == "\"7:abc\"")
    }

    @Test func fetchOmitsIfNoneMatchWhenNoEtagIsKnown() async throws {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 200, headers: ["ETag": "\"7:abc\""], body: envelope())])
        let fetcher = makeFetcher(transport: transport)

        _ = try await fetcher.fetch(ifNoneMatch: nil)

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].headers["If-None-Match"] == nil, "a first fetch must not send If-None-Match")
    }

    @Test func fetchReturnsNilOn304() async throws {
        let transport = RecordingTransport()
        // 304 with an empty body: the held document stands.
        transport.script([TankbookHTTPResponse(status: 304, headers: ["ETag": "\"7:abc\""], body: nil)])
        let fetcher = makeFetcher(transport: transport)

        let result = try await fetcher.fetch(ifNoneMatch: "\"7:abc\"")

        #expect(result == nil, "a 304 must resolve to nil, never to a document")
    }

    @Test func fetchExtractsTheDocumentVerbatimAndCarriesTheEtag() async throws {
        let transport = RecordingTransport()
        let signature = "c2lnbmF0dXJlLW9mLXRoaXMtZG9j"
        transport.script([TankbookHTTPResponse(
            status: 200,
            headers: ["ETag": "\"7:abc123\""],
            body: envelope(signature: signature)
        )])
        let fetcher = makeFetcher(transport: transport)

        let result = try #require(try await fetcher.fetch(ifNoneMatch: nil))

        #expect(result.document == Data(rawDocument.utf8),
                "the document bytes must be extracted verbatim, not re-serialized")
        #expect(result.signature == signature)
        #expect(result.etag == "\"7:abc123\"")
    }

    @Test func fetchRequestsTheVersionedConfigEndpointUnderTheResolvedBaseURL() async throws {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 200, headers: ["ETag": "\"7:x\""], body: envelope())])
        let fetcher = makeFetcher(transport: transport, baseURL: URL(string: "https://eu.api.tankbook.live")!)

        _ = try await fetcher.fetch(ifNoneMatch: nil)

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].url == URL(string: "https://eu.api.tankbook.live/v1/config")!)
    }

    @Test func fetchThrowsOnANonSuccessStatus() async {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 503, body: nil)])
        let fetcher = makeFetcher(transport: transport)

        await #expect(throws: RemoteConfigFetcherError.unexpectedStatus(503)) {
            _ = try await fetcher.fetch(ifNoneMatch: nil)
        }
    }

    @Test func fetchThrowsOnAMalformedEnvelope() async {
        let transport = RecordingTransport()
        transport.script([TankbookHTTPResponse(status: 200, body: Data("{\"nope\":true}".utf8))])
        let fetcher = makeFetcher(transport: transport)

        await #expect(throws: RemoteConfigFetcherError.malformedEnvelope) {
            _ = try await fetcher.fetch(ifNoneMatch: nil)
        }
    }
}
