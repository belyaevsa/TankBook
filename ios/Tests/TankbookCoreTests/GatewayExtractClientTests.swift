import Foundation
import os
import Testing
@testable import TankbookCore

// P6.3 - the /extract client decodes the wire response and consumes the P6.11
// server classification (SyncServerError) instead of re-classifying it.

@Suite("LLM gateway wire client (P6.3)")
struct GatewayExtractClientTests {

    // MARK: - Decoding the response

    @Test("decodes a full field set with per-field confidence")
    func decodesFullFieldSet() throws {
        let data = Data(#"""
        {
          "fields": {
            "total":     { "value": 71.02,     "confidence": 0.95 },
            "volume":    { "value": 42.30,     "confidence": 0.9 },
            "unitPrice": { "value": 1.679,     "confidence": 0.88 },
            "date":      { "value": "17.08.2026", "confidence": 0.8 },
            "fuelKind":  { "value": "petrol95",   "confidence": 0.7 },
            "currency":  { "value": "RUB",        "confidence": 0.6 }
          },
          "pipeline": "cloud-fallback v1"
        }
        """#.utf8)
        let extraction = try GatewayExtraction.decode(data)

        #expect(extraction.pipeline == "cloud-fallback v1")
        #expect(extraction.total?.value == Decimal(string: "71.02"))
        #expect(extraction.total?.confidence == 0.95)
        #expect(extraction.volume?.value == 42.30)
        #expect(extraction.volume?.confidence == 0.9)
        #expect(extraction.unitPrice?.value == Decimal(string: "1.679"))
        #expect(extraction.unitPrice?.confidence == 0.88)
        #expect(extraction.date?.value == "17.08.2026")
        #expect(extraction.fuelKind?.value == .petrol95)
        #expect(extraction.currency?.value == .rub)
        #expect(extraction.providedFields == [.total, .volume, .unitPrice, .date, .fuelKind, .currency])
    }

    @Test("money keeps its exact decimal from the raw token, never through Double")
    func moneyIsExactDecimal() throws {
        // A value like 2747.16 must survive as the exact Decimal, not a
        // binary-float neighbour - the P2.2b money boundary, applied to the
        // gateway wire the same way.
        let data = Data(#"{"fields":{"total":{"value":2747.16,"confidence":0.9}},"pipeline":"p"}"#.utf8)
        let extraction = try GatewayExtraction.decode(data)
        #expect(extraction.total?.value == Decimal(string: "2747.16"))
    }

    @Test("unknown field refs and unparseable values are skipped, not fatal")
    func unknownFieldsAreSkipped() throws {
        // A newer server may send fields this client does not render, or a
        // value this client cannot map (e.g. an unexpected fuelKind string).
        let data = Data(#"""
        {
          "fields": {
            "station":  { "value": "Circle K",      "confidence": 0.9 },
            "energy":   { "value": 12.5,            "confidence": 0.8 },
            "vendor":   { "value": "Orlen",         "confidence": 0.7 },
            "fuelKind": { "value": "not-a-kind",    "confidence": 0.5 },
            "total":    { "value": 71.02,           "confidence": 0.9 }
          },
          "pipeline": "p"
        }
        """#.utf8)
        let extraction = try GatewayExtraction.decode(data)
        #expect(extraction.total?.value == Decimal(string: "71.02"))
        // The unknown refs and the unparseable enum value are simply absent.
        #expect(extraction.providedFields == [.total])
    }

    @Test("an unparseable body is an invalidResponse, never a crash")
    func malformedBodyIsInvalidResponse() {
        #expect(throws: GatewayExtractError.invalidResponse) {
            _ = try GatewayExtraction.decode(Data("not json".utf8))
        }
        #expect(throws: GatewayExtractError.invalidResponse) {
            _ = try GatewayExtraction.decode(Data("[1,2,3]".utf8))
        }
    }

    // MARK: - Status codes consume SyncServerError (P6.11), never re-classify

    private struct StubTransport: TankbookHTTPTransport {
        let status: Int
        let body: Data?
        let retryAfter: String?
        let recorded = RecordingBox()

        func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
            recorded.request = request
            var headers: [String: String] = [:]
            if let retryAfter { headers["Retry-After"] = retryAfter }
            return TankbookHTTPResponse(status: status, headers: headers, body: body)
        }
    }

    private static func makeClient(_ transport: any TankbookHTTPTransport) -> RemoteGatewayExtractTransport {
        RemoteGatewayExtractTransport(
            director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! }, report: { _ in }),
            transport: transport,
            tokenProvider: StaticTokenProvider())
    }

    private static func request() -> GatewayExtractRequest {
        .init(kind: "receipt", imageJPEG: Data("jpeg-bytes".utf8))
    }

    @Test("402 maps to tierRefused, 429 carries Retry-After, 426 to upgradeRequired")
    func tierAndVersionCodesMapToSyncServerError() async {
        await #expect(throws: SyncServerError.tierRefused) {
            _ = try await Self.makeClient(StubTransport(status: 402, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
        await #expect(throws: SyncServerError.upgradeRequired) {
            _ = try await Self.makeClient(StubTransport(status: 426, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
        await #expect(throws: SyncServerError.rateLimited(retryAfterSeconds: 42)) {
            _ = try await Self.makeClient(StubTransport(status: 429, body: nil, retryAfter: "42"))
                .extract(Self.request())
        }
        await #expect(throws: SyncServerError.rateLimited(retryAfterSeconds: nil)) {
            _ = try await Self.makeClient(StubTransport(status: 429, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
    }

    @Test("an unknown 4xx is refused(status:), never a generic failure")
    func unknownFourXxMapsToRefused() async {
        await #expect(throws: SyncServerError.refused(status: 451)) {
            _ = try await Self.makeClient(StubTransport(status: 451, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
    }

    /// A 401 is an auth event, never an unknown gate (PR.1, RV.65): a 401 that
    /// outlives refresh-and-retry means the server rejects this session, so the
    /// honest next step is "sign in again", not "update the app" - the same
    /// classification the sync and blob transports use.
    @Test("a 401 is authExpired, never refused(status:)")
    func a401IsAuthExpired() async {
        await #expect(throws: SyncServerError.authExpired) {
            _ = try await Self.makeClient(StubTransport(status: 401, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
    }

    @Test("a 5xx or transport failure is transportUnavailable")
    func serverFailureIsTransportUnavailable() async {
        await #expect(throws: SyncServerError.transportUnavailable) {
            _ = try await Self.makeClient(StubTransport(status: 502, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
        await #expect(throws: SyncServerError.transportUnavailable) {
            _ = try await Self.makeClient(StubTransport(status: 500, body: nil, retryAfter: nil))
                .extract(Self.request())
        }
    }

    @Test("a 200 decodes the body; a host outside the allowlist is refused before I/O")
    func successDecodesAndAllowlistIsEnforced() async throws {
        let body = Data(#"{"fields":{"total":{"value":71.02,"confidence":0.9}},"pipeline":"p"}"#.utf8)
        let stub = StubTransport(status: 200, body: body, retryAfter: nil)
        let extraction = try await Self.makeClient(stub).extract(Self.request())
        #expect(extraction.total?.value == Decimal(string: "71.02"))

        // The allowlist is a TankbookHTTPClient rule, and it applies to this
        // client exactly as to auth and sync.
        let outside = RemoteGatewayExtractTransport(
            director: ConfigTransportDirector(baseURL: { URL(string: "https://evil.example")! }, report: { _ in }),
            transport: stub,
            tokenProvider: StaticTokenProvider())
        await #expect(throws: SyncServerError.transportUnavailable) {
            _ = try await outside.extract(Self.request())
        }
    }

    @Test("the request body is the documented envelope: kind, base64 image, optional hints")
    func requestEnvelopeShape() async throws {
        let body = Data(#"{"fields":{},"pipeline":"p"}"#.utf8)
        let stub = StubTransport(status: 200, body: body, retryAfter: nil)
        let client = Self.makeClient(stub)
        var request = Self.request()
        request.hints = GatewayExtractHints(currency: "EUR", locale: "ru_RU", vehicleFuelKinds: ["petrol95", "diesel"])
        _ = try await client.extract(request)

        let sent = try #require(stub.recorded.request)
        #expect(sent.url.path == "/v1/extract")
        #expect(sent.method == "POST")
        #expect(sent.headers["Content-Type"] == "application/json")
        let tree = try JSONValue.parse(#require(sent.body))
        let object = try #require(tree.objectValue)
        #expect(object["kind"]?.stringValue == "receipt")
        #expect(object["image"]?.stringValue == Data("jpeg-bytes".utf8).base64EncodedString())
        let hints = try #require(object["hints"]?.objectValue)
        #expect(hints["currency"]?.stringValue == "EUR")
        #expect(hints["locale"]?.stringValue == "ru_RU")
        #expect(hints["vehicleFuelKinds"]?.arrayValue?.compactMap(\.stringValue) == ["petrol95", "diesel"])
    }

    @Test("an envelope over the 4 MB base64 cap is refused locally, never uploaded")
    func oversizeEnvelopeIsRefusedLocally() async throws {
        let body = Data(#"{"fields":{},"pipeline":"p"}"#.utf8)
        let stub = StubTransport(status: 200, body: body, retryAfter: nil)
        let client = Self.makeClient(stub)
        // 3 MB + 1 byte of JPEG bytes -> just over 4 MB of base64: over the cap.
        let oversized = Data(repeating: 0xA5, count: 3 * 1024 * 1024 + 1)
        let request = GatewayExtractRequest(kind: "receipt", imageJPEG: oversized)
        await #expect(throws: GatewayExtractError.envelopeTooLarge) {
            _ = try await client.extract(request)
        }
        #expect(stub.recorded.request == nil,
                "an oversized envelope must never reach the transport")
    }

    // MARK: - The one silent retry (PR.7, docs/API.md -> "Retries are the
    // device's business, not the user's: one silent retry at most").

    @Test("a transient failure retries once, then succeeds")
    func transientFailureRetriesOnceThenSucceeds() async throws {
        let stub = ScriptedTransport(responses: [
            TankbookHTTPResponse(status: 502, headers: [:], body: nil),
            TankbookHTTPResponse(status: 200, headers: [:],
                                 body: Data(#"{"fields":{},"pipeline":"p"}"#.utf8))
        ])
        let extraction = try await Self.makeClient(stub).extract(Self.request())
        #expect(extraction.pipeline == "p")
        #expect(stub.callCount == 2, "exactly one silent retry: two attempts total")
    }

    @Test("a transient failure surfaces after exactly one retry, never two")
    func transientFailureSurfacesAfterOneRetry() async {
        let stub = ScriptedTransport(responses: [
            TankbookHTTPResponse(status: 503, headers: [:], body: nil),
            TankbookHTTPResponse(status: 503, headers: [:], body: nil)
        ])
        await #expect(throws: SyncServerError.transportUnavailable) {
            _ = try await Self.makeClient(stub).extract(Self.request())
        }
        #expect(stub.callCount == 2, "one silent retry at most, never two")
    }

    @Test("a refusal is never retried")
    func refusalIsNeverRetried() async {
        let stub = ScriptedTransport(responses: [
            TankbookHTTPResponse(status: 429, headers: ["Retry-After": "120"], body: nil)
        ])
        await #expect(throws: SyncServerError.rateLimited(retryAfterSeconds: 120)) {
            _ = try await Self.makeClient(stub).extract(Self.request())
        }
        #expect(stub.callCount == 1, "a refusal surfaces immediately, never retried")
    }
}

/// A transport that returns scripted responses in order (the last one repeats),
/// counting every call - the harness for the one-silent-retry behaviour.
private final class ScriptedTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var responses: [TankbookHTTPResponse]
        var calls = 0
    }
    private let state: OSAllocatedUnfairLock<State>

    init(responses: [TankbookHTTPResponse]) {
        state = OSAllocatedUnfairLock(initialState: State(responses: responses))
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        state.withLock { snapshot in
            snapshot.calls += 1
            if snapshot.responses.count > 1 {
                return snapshot.responses.removeFirst()
            }
            return snapshot.responses.first ?? Self.success
        }
    }

    var callCount: Int {
        state.withLock { $0.calls }
    }

    private static let success = TankbookHTTPResponse(
        status: 200, headers: [:], body: Data(#"{"fields":{},"pipeline":"p"}"#.utf8))
}

private final class RecordingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TankbookHTTPRequest?
    var request: TankbookHTTPRequest? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

private struct StaticTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { "test-token" }
}
