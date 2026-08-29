import Foundation
import os
import Testing
@testable import TankbookCore

// P6.4 - the account & devices wire client (docs/API.md -> "Account &
// devices"): decodes the device list as the backend serializes it (including
// the round-trip DateTimeOffset the screen cannot afford to blank), maps the
// per-status errors, and sends the two DELETE verbs to the exact paths. The
// screen's guarantees (local data stays local on revoke AND on delete) are
// enforced at the UI layer; here the client just has to be faithful to the wire.

// MARK: - Doubles

private final class AccountTestTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var responses: [TankbookHTTPResponse] = []
        var received: [TankbookHTTPRequest] = []
        var shouldFail = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0.responses = responses }
    }

    func failAllRequests() {
        lock.withLock { $0.shouldFail = true }
    }

    func receivedRequests() -> [TankbookHTTPRequest] {
        lock.withLock { $0.received }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        try lock.withLock { state in
            state.received.append(request)
            if state.shouldFail { throw URLError(.notConnectedToInternet) }
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200) }
            return state.responses.removeFirst()
        }
    }
}

private final class AccountTestTokenProvider: AuthorizationTokenProvider, @unchecked Sendable {
    func token() -> String? { "test-token" }
}

private func makeClient(transport: AccountTestTransport) -> AccountClient {
    let client = TankbookHTTPClient(transport: transport,
                                    tokenProvider: AccountTestTokenProvider())
    return AccountClient(httpClient: client,
                         director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! },
                                                           report: { _ in }))
}

@Suite("Account & devices wire client (P6.4)")
struct AccountClientTests {

    // MARK: - GET /account/devices

    @Test("decodes the device list with revoked markers and offset timestamps")
    func decodesDeviceList() async throws {
        let transport = AccountTestTransport()
        transport.script([TankbookHTTPResponse(
            status: 200,
            body: Data("""
            {
              "devices": [
                { "id": "11111111-1111-1111-1111-111111111111",
                  "name": "Alex's iPhone", "platform": "iOS",
                  "lastSeenAt": "2026-08-28T10:30:00.0000000+02:00", "revoked": false },
                { "id": "22222222-2222-2222-2222-222222222222",
                  "name": "Home iPad", "platform": "iPadOS",
                  "lastSeenAt": "2026-07-01T00:00:00Z", "revoked": true }
              ]
            }
            """.utf8))])
        let client = makeClient(transport: transport)
        let devices = try await client.devices()

        #expect(devices.count == 2)
        #expect(devices[0].name == "Alex's iPhone")
        #expect(devices[0].platform == "iOS")
        #expect(devices[0].revoked == false)
        #expect(devices[1].revoked == true)
        #expect(devices[0].id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        // The request hit /v1/account/devices with the bearer attached.
        let request = try #require(transport.receivedRequests().first)
        #expect(request.url.path == "/v1/account/devices")
        #expect(request.method == "GET")
        #expect(request.headers["Authorization"] == "Bearer test-token")
    }

    @Test("a seven-digit fraction is normalized, not fatal")
    func decodesRoundTripFraction() async throws {
        let transport = AccountTestTransport()
        let json = #"{"devices":[{"id":"11111111-1111-1111-1111-111111111111","name":"x","platform":"iOS","lastSeenAt":"2026-08-28T10:30:00.1234567Z""# +
            #","revoked":false}]}"#
        transport.script([TankbookHTTPResponse(status: 200, body: Data(json.utf8))])
        let client = makeClient(transport: transport)
        let devices = try await client.devices()
        #expect(devices.count == 1)
        // The date is parsed, not blanked - a schema evolution must not erase
        // a device's last-seen line.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try #require(formatter.date(from: "2026-08-28T10:30:00.123Z"))
        #expect(abs(devices[0].lastSeenAt.timeIntervalSince(expected)) < 1)
    }

    @Test("a malformed body is invalidResponse, never a crash")
    func malformedBodyIsInvalidResponse() async {
        let transport = AccountTestTransport()
        transport.script([TankbookHTTPResponse(status: 200, body: Data("not json".utf8))])
        let client = makeClient(transport: transport)
        await #expect(throws: AccountClientError.invalidResponse) {
            _ = try await client.devices()
        }
    }

    // MARK: - DELETE /account/devices/{id}

    @Test("revoke sends DELETE to the exact device path and accepts 204")
    func revokeDevice() async throws {
        let transport = AccountTestTransport()
        transport.script([TankbookHTTPResponse(status: 204)])
        let client = makeClient(transport: transport)
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        try await client.revoke(deviceID: id)

        let request = try #require(transport.receivedRequests().first)
        #expect(request.method == "DELETE")
        #expect(request.url.path == "/v1/account/devices/33333333-3333-3333-3333-333333333333")
        #expect(request.headers["Authorization"] == "Bearer test-token")
    }

    // MARK: - DELETE /account

    @Test("deleteAccount sends DELETE to /v1/account and accepts 204")
    func deleteAccount() async throws {
        let transport = AccountTestTransport()
        transport.script([TankbookHTTPResponse(status: 204)])
        let client = makeClient(transport: transport)
        try await client.deleteAccount()

        let request = try #require(transport.receivedRequests().first)
        #expect(request.method == "DELETE")
        #expect(request.url.path == "/v1/account")
    }

    // MARK: - Error mapping

    @Test("401 maps to unauthorized, 404 to notFound, 500 to server")
    func mapsStatusErrors() async throws {
        for (status, expected) in [(401, AccountClientError.unauthorized),
                                   (404, AccountClientError.notFound),
                                   (500, AccountClientError.server(status: 500))] {
            let transport = AccountTestTransport()
            transport.script([TankbookHTTPResponse(status: status)])
            let client = makeClient(transport: transport)
            await #expect(throws: expected) {
                _ = try await client.devices()
            }
        }
    }

    @Test("a transport failure is transportUnreachable, never a status lie")
    func transportFailureMaps() async {
        let transport = AccountTestTransport()
        transport.failAllRequests()
        let client = makeClient(transport: transport)
        await #expect(throws: AccountClientError.transportUnreachable) {
            _ = try await client.devices()
        }
    }

    @Test("a non-allowlisted host is refused before any I/O")
    func nonAllowlistedHostIsRefused() async throws {
        let transport = AccountTestTransport()
        let httpClient = TankbookHTTPClient(transport: transport,
                                            tokenProvider: AccountTestTokenProvider())
        let client = AccountClient(httpClient: httpClient,
                                   director: ConfigTransportDirector(baseURL: { URL(string: "https://evil.example")! },
                                                                     report: { _ in }))
        await #expect(throws: AccountClientError.client) {
            _ = try await client.devices()
        }
        #expect(transport.receivedRequests().isEmpty, "no request must go out")
    }
}
