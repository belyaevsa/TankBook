import Foundation
import os
import Testing
@testable import TankbookCore

// PR.9/OB.1 - the client half of the coded error envelope (docs/API.md ->
// "Error envelope"). Two guarantees are pinned here, both at the level where the
// user-visible message is decided (the typed error each surface renders):
//
// 1. A KNOWN code refines the classification beyond what the status alone said
//    - the whole point of the field (RV.65's "session expired" used to have to
//    be guessed from a 401; a code lets the server actually say which one).
// 2. An UNKNOWN code falls back to the status-based classification - never a
//    blank, never a raw identifier, never a new failure class this client
//    would not have chosen for the status itself. That is the compatibility
//    guarantee: an older client survives a code a newer server added.

private struct NoTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { "test-token" }
}

private let apiURL = URL(string: "https://api.tankbook.live")!

private func director() -> ConfigTransportDirector {
    ConfigTransportDirector(baseURL: { apiURL }, report: { _ in })
}

/// One-shot scripted response transport.
private final class ScriptTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [TankbookHTTPResponse]())
    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0 = responses }
    }
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { state in
            guard !state.isEmpty else { return TankbookHTTPResponse(status: 200) }
            return state.removeFirst()
        }
    }
}

private func problemBody(code: String?) -> Data {
    var object: [String: Any] = ["title": "x", "status": 400, "detail": "x"]
    object["traceId"] = "trace-abc"
    if let code { object["code"] = code }
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

// MARK: - The transport carries the code (single parse point)

@Suite("The coded error envelope is parsed once and carried (PR.9)")
struct ServerErrorCodeParsingTests {

    private func makeClient(_ transport: ScriptTransport) -> TankbookHTTPClient {
        TankbookHTTPClient(transport: transport, tokenProvider: NoTokenProvider())
    }

    @Test("a problem+json code rides the thrown httpError alongside traceId")
    func codeIsCarriedOnTheError() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 422, body: problemBody(code: "payload_invalid"))])
        let client = makeClient(transport)
        do {
            _ = try await client.send(TankbookHTTPRequest(url: apiURL))
            Issue.record("expected an httpError")
        } catch let TankbookHTTPClientError.httpError(status, code, traceId, retryAfter) {
            #expect(status == 422)
            #expect(code == "payload_invalid")
            #expect(traceId == "trace-abc")
            #expect(retryAfter == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("an unknown code is carried raw (loggable), never dropped or rejected")
    func unknownCodeIsCarriedRaw() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 418, body: problemBody(code: "brand_new_future_code"))])
        let client = makeClient(transport)
        do {
            _ = try await client.send(TankbookHTTPRequest(url: apiURL))
            Issue.record("expected an httpError")
        } catch let TankbookHTTPClientError.httpError(_, code, _, _) {
            #expect(code == "brand_new_future_code",
                    "the raw code must survive for logging even when unknown")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("a body without a code yields nil - today's servers stay readable")
    func absentCodeYieldsNil() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 500, body: Data("{}".utf8))])
        let client = makeClient(transport)
        do {
            _ = try await client.send(TankbookHTTPRequest(url: apiURL))
            Issue.record("expected an httpError")
        } catch let TankbookHTTPClientError.httpError(status, code, _, _) {
            #expect(status == 500)
            #expect(code == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

// MARK: - Auth: the code the status could not say

@Suite("Auth code mapping (PR.9)")
struct AuthCodeMappingTests {

    private func makeService(_ transport: ScriptTransport) -> RemoteAuthService {
        RemoteAuthService(
            director: ConfigTransportDirector(baseURL: { apiURL }, report: { _ in }),
            transport: transport,
            sessionStore: InMemorySessionStore(),
            device: RemoteAuthService.SessionDevice(name: "iPhone", platform: "iOS"))
    }

    private func identity() -> ProviderIdentity {
        ProviderIdentity(provider: .apple, idToken: "id-token", email: "d@example.com")
    }

    @Test("clock_skew names the real next step: fix the device date")
    func clockSkewCodeIsDistinct() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 401, body: problemBody(code: "clock_skew"))])
        await #expect(throws: AuthError.clockSkew) {
            _ = try await makeService(transport).signIn(identity: identity())
        }
    }

    @Test("token_invalid and provider_unsupported keep their auth classes")
    func authCodesKeepTheirClasses() async {
        let invalid = ScriptTransport()
        invalid.script([TankbookHTTPResponse(status: 401, body: problemBody(code: "token_invalid"))])
        await #expect(throws: AuthError.unauthorized) {
            _ = try await makeService(invalid).signIn(identity: identity())
        }

        let unsupported = ScriptTransport()
        unsupported.script([TankbookHTTPResponse(status: 400, body: problemBody(code: "provider_unsupported"))])
        await #expect(throws: AuthError.unsupportedProvider) {
            _ = try await makeService(unsupported).signIn(identity: identity())
        }
    }

    @Test("an unknown code falls back to the status classification")
    func unknownCodeFallsBackToStatus() async {
        // 400 with an unknown code is .badRequest - exactly what a code-less 400 is.
        let badRequest = ScriptTransport()
        badRequest.script([TankbookHTTPResponse(status: 400, body: problemBody(code: "some_new_shape_code"))])
        await #expect(throws: AuthError.badRequest) {
            _ = try await makeService(badRequest).signIn(identity: identity())
        }
        // 500 with an unknown code is .invalidResponse - never blank/raw.
        let server = ScriptTransport()
        server.script([TankbookHTTPResponse(status: 500, body: problemBody(code: "some_new_server_code"))])
        await #expect(throws: AuthError.invalidResponse) {
            _ = try await makeService(server).signIn(identity: identity())
        }
    }
}

// MARK: - Account: a code refines a status that would otherwise be ambiguous

@Suite("Account code mapping (PR.9)")
struct AccountCodeMappingTests {

    private func makeClient(_ transport: ScriptTransport) -> AccountClient {
        AccountClient(httpClient: TankbookHTTPClient(transport: transport, tokenProvider: NoTokenProvider()),
                      director: ConfigTransportDirector(baseURL: { apiURL }, report: { _ in }))
    }

    @Test("token_invalid at any status is an auth event, not a server failure")
    func tokenInvalidRefinesAnyStatus() async {
        // The status says 400; the code says the session is gone. The code wins,
        // because the surface's next step (sign in again) is the one that helps.
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 400, body: problemBody(code: "token_invalid"))])
        await #expect(throws: AccountClientError.unauthorized) {
            _ = try await makeClient(transport).devices()
        }
    }

    @Test("account_device_not_found maps to notFound even under another status")
    func deviceNotFoundCode() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 403, body: problemBody(code: "account_device_not_found"))])
        await #expect(throws: AccountClientError.notFound) {
            _ = try await makeClient(transport).devices()
        }
    }

    @Test("an unknown code falls back to the status classification")
    func unknownCodeFallsBackToStatus() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 403, body: problemBody(code: "future_gate_code"))])
        await #expect(throws: AccountClientError.server(status: 403)) {
            _ = try await makeClient(transport).devices()
        }
    }
}

// MARK: - Sync: unknown codes degrade to today's status reading

@Suite("Sync code mapping (PR.9)")
struct SyncCodeMappingTests {

    private func makeTransport(_ status: Int, code: String?) -> RemoteSyncTransport {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: status, body: problemBody(code: code))])
        return RemoteSyncTransport(
            director: ConfigTransportDirector(baseURL: { apiURL }, report: { _ in }),
            transport: transport,
            tokenProvider: NoTokenProvider())
    }

    private func pullError(_ status: Int, code: String?) async -> SyncServerError? {
        do {
            _ = try await makeTransport(status, code: code).pull(since: 0, limit: 10)
            return nil
        } catch let error as SyncServerError {
            return error
        } catch {
            return nil
        }
    }

    @Test("an unknown code equals the status-only classification, never blank/raw")
    func unknownCodeFallsBackToStatus() async {
        for (status, code) in [(403, "future_gate"), (500, "future_server"), (410, "future_revoke")] {
            let coded = await pullError(status, code: code)
            let statusOnly = await pullError(status, code: nil)
            #expect(coded == statusOnly,
                    "an unknown code must read exactly as today's status did")
            #expect(coded != nil, "the unknown code must never vanish into a blank")
        }
    }

    @Test("a known code still refines when the status alone would mislead")
    func knownCodeRefinesStatus() async {
        // A 401 + device_revoked is the 410 meaning under a status the old
        // client would have read as authExpired - the code must win.
        #expect(await pullError(401, code: "device_revoked") == .deviceRevoked)
        #expect(await pullError(400, code: "rate_limited") == .rateLimited(retryAfterSeconds: nil))
    }
}

// MARK: - Import & blobs

@Suite("Import code mapping (PR.9)")
struct ImportCodeMappingTests {

    private func makeClient(_ transport: ScriptTransport) -> ImportClient {
        ImportClient(httpClient: TankbookHTTPClient(transport: transport, tokenProvider: NoTokenProvider()),
                     director: ConfigTransportDirector(baseURL: { apiURL }, report: { _ in }),
                     deviceID: "device-1")
    }

    @Test("import_mismatch and import_format_unsupported map to their own classes")
    func importCodesKeepTheirClasses() async {
        let mismatch = ScriptTransport()
        mismatch.script([TankbookHTTPResponse(status: 400, body: problemBody(code: "import_mismatch"))])
        await #expect(throws: ImportClientError.doesNotMatchDeclared(displayName: "My Fuel Manager")) {
            _ = try await makeClient(mismatch).parseFile(data: Data("x".utf8), fileName: "x.csv",
                                                         format: ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                                              fileKinds: ["csv"], helpUrl: nil, addedInPackVersion: 1))
        }

        let unsupported = ScriptTransport()
        unsupported.script([TankbookHTTPResponse(status: 400, body: problemBody(code: "import_format_unsupported"))])
        await #expect(throws: ImportClientError.unrecognisedFormat) {
            _ = try await makeClient(unsupported).fetchFormats()
        }
    }

    @Test("an unknown code falls back to the status classification")
    func unknownCodeFallsBackToStatus() async {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: 413, body: problemBody(code: "future_size_code"))])
        await #expect(throws: ImportClientError.oversize) {
            _ = try await makeClient(transport).fetchFormats()
        }
    }
}

@Suite("Blob code mapping (PR.9)")
struct BlobCodeMappingTests {

    private func makeTransport(_ status: Int, code: String?) -> RemoteBlobTransport {
        let transport = ScriptTransport()
        transport.script([TankbookHTTPResponse(status: status, body: problemBody(code: code))])
        return RemoteBlobTransport(
            director: ConfigTransportDirector(baseURL: { apiURL }, report: { _ in }),
            transport: transport,
            tokenProvider: NoTokenProvider())
    }

    private func downloadError(_ status: Int, code: String?) async -> BlobSyncError? {
        do {
            _ = try await makeTransport(status, code: code).download(sha256: String(repeating: "a", count: 64))
            return nil
        } catch let error as BlobSyncError {
            return error
        } catch {
            return nil
        }
    }

    @Test("blob_not_found maps to notFound even under an off status")
    func blobNotFoundCode() async {
        #expect(await downloadError(500, code: "blob_not_found") == .notFound)
    }

    @Test("an unknown code falls back to the status classification")
    func unknownCodeFallsBackToStatus() async {
        #expect(await downloadError(404, code: "future_code") == .notFound)
        #expect(await downloadError(413, code: "future_code") == .sizeExceeded)
        #expect(await downloadError(429, code: "future_code") == .quotaExceeded)
    }
}
