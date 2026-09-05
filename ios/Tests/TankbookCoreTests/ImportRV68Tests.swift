import Foundation
import os
import Testing
@testable import TankbookCore

// RV.68 - the import client's non-HTTP error mapping (docs/TASKS.md RV.68).
// Every error class is driven through the client exactly as the transport
// would throw it, and the mapped `ImportClientError` - and the source-step
// STATE it renders (docs/ERRORS.md -> Import wizard) - are asserted. The
// assertion is on the state, never on "an error was thrown": one already threw,
// and the defect was that the WRONG state followed. Runs in a plain `swift
// test` process over an injected transport - no sockets (docs/TESTING.md).

// MARK: - Doubles (self-contained: each test file owns its transport doubles)

private final class RV68TestTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var responses: [TankbookHTTPResponse] = []
        var received: [TankbookHTTPRequest] = []
        var oneShotFailure: Error?
        var persistentFailure: Error?
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { state in
            state.responses = responses
            state.oneShotFailure = nil
            state.persistentFailure = nil
        }
    }

    /// Makes the next `execute` throw `error`.
    func fail(with error: Error) {
        lock.withLock { state in
            state.oneShotFailure = error
            state.persistentFailure = nil
        }
    }

    /// Makes every `execute` throw `URLError.notConnectedToInternet` (the
    /// genuinely-offline case is a standing state, not one request).
    func failAllRequests() {
        lock.withLock { state in
            state.persistentFailure = URLError(.notConnectedToInternet)
            state.oneShotFailure = nil
        }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        try lock.withLock { state in
            state.received.append(request)
            if let failure = state.oneShotFailure {
                state.oneShotFailure = nil
                throw failure
            }
            if let failure = state.persistentFailure { throw failure }
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200) }
            return state.responses.removeFirst()
        }
    }
}

private final class RV68TestTokenProvider: AuthorizationTokenProvider, @unchecked Sendable {
    func token() -> String? { "test-token" }
}

/// Records the outcomes reported to the config director so a test can assert
/// what a failure did (and did not) feed the base-URL guardrails
/// (docs/CONFIG.md): a cancellation must never report `.transportFailure`.
private final class RV68OutcomeRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [ConfigTransportOutcome]())
    func record(_ outcome: ConfigTransportOutcome) { lock.withLock { $0.append(outcome) } }
    func outcomes() -> [ConfigTransportOutcome] { lock.withLock { $0 } }
}

private func rv68Client(transport: RV68TestTransport,
                        log: TankbookLog? = nil,
                        recorder: RV68OutcomeRecorder? = nil) -> ImportClient {
    let client = TankbookHTTPClient(transport: transport,
                                    tokenProvider: RV68TestTokenProvider())
    return ImportClient(httpClient: client,
                        director: ConfigTransportDirector(
                            baseURL: { URL(string: "https://api.tankbook.live")! },
                            report: { recorder?.record($0) }),
                        deviceID: "device-123",
                        log: log)
}

// MARK: - The suite

@Suite("Import non-HTTP error mapping (RV.68)")
struct ImportNonHTTPMappingTests {

    /// Drives `fetchFormats` against a transport that throws exactly `error`,
    /// returning the mapped `ImportClientError` the test asserts.
    private func mappedError(for error: Error,
                             recorder: RV68OutcomeRecorder? = nil) async throws -> ImportClientError? {
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport, recorder: recorder)
        transport.fail(with: error)
        do {
            _ = try await client.fetchFormats()
            return nil
        } catch let mapped as ImportClientError {
            return mapped
        } catch {
            return nil
        }
    }

    /// The connectivity family - the ONLY errors that may map to the offline
    /// state. The case that used to work must keep working (it is the one that
    /// was never broken).
    @Test func connectivityFamilyMapsToTransportUnreachable() async throws {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .timedOut,
            .dataNotAllowed, .internationalRoamingOff
        ]
        for code in codes {
            let mapped = try await mappedError(for: URLError(code))
            #expect(mapped == .transportUnreachable,
                    "URLError.\(code.rawValue) must map to transportUnreachable, got \(String(describing: mapped))")
        }
    }

    @Test func aGenuinelyOfflineTransportStillReportsATransportFailure() async throws {
        // Connectivity is the one class that legitimately feeds the base-URL
        // auto-revert guardrails (docs/CONFIG.md).
        let recorder = RV68OutcomeRecorder()
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport, recorder: recorder)
        transport.failAllRequests()
        await #expect(throws: ImportClientError.transportUnreachable) {
            _ = try await client.fetchFormats()
        }
        #expect(recorder.outcomes().contains(.transportFailure),
                "a genuine connectivity failure must report to the config director")
    }

    @Test func aCancellationIsNotAnErrorState() async throws {
        // RV.68: a cancelled URLSession task throws URLError.cancelled, which
        // used to land in the catch-all and render the offline card. A
        // cancellation is not a failure - it must surface as `.cancelled`,
        // never as transportUnreachable.
        let recorder = RV68OutcomeRecorder()
        let mapped = try await mappedError(for: URLError(.cancelled), recorder: recorder)
        #expect(mapped == .cancelled,
                "URLError.cancelled must map to .cancelled, got \(String(describing: mapped))")
        #expect(!recorder.outcomes().contains(.transportFailure),
                "a cancellation is no evidence against the base URL and must not report .transportFailure")
    }

    @Test func aSwiftCancellationIsNotAnErrorState() async throws {
        let mapped = try await mappedError(for: CancellationError())
        #expect(mapped == .cancelled)
    }

    @Test func aTLSErrorIsNotOffline() async throws {
        // A TLS handshake failure happens on a working network - telling the
        // user to check their connection would send them to fix something that
        // is not broken (hard rule 7).
        let mapped = try await mappedError(for: URLError(.secureConnectionFailed))
        #expect(mapped == .transportFailure,
                "a TLS failure must not map to transportUnreachable, got \(String(describing: mapped))")
    }

    @Test func anUndecodableBodyIsAContractErrorNotOffline() async throws {
        // A decode failure is a client/server contract bug, never "you need a
        // connection".
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport)
        transport.script([TankbookHTTPResponse(status: 200, body: Data("not the formats json".utf8))])
        await #expect(throws: ImportClientError.invalidResponse) {
            _ = try await client.fetchFormats()
        }
    }

    @Test func a500IsAServerErrorNotOffline() async throws {
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport)
        transport.script([TankbookHTTPResponse(status: 500)])
        await #expect(throws: ImportClientError.server(status: 500)) {
            _ = try await client.fetchFormats()
        }
    }

    @Test func theUnderlyingErrorIsLoggedBeforeMappingWithNoPayload() async throws {
        // RV.68's first deliverable: the mapping is reconstructible from the
        // log. The event carries the route path, the error's Swift type and the
        // URLError code - and nothing else (hard rule 12: never a payload, a
        // query or a rendered message).
        let sink = InMemorySink()
        let log = TankbookLog.makeDefault(sink: sink, deviceId: nil, breadcrumbs: nil)
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport, log: log)
        transport.fail(with: URLError(.timedOut))

        await #expect(throws: ImportClientError.transportUnreachable) {
            _ = try await client.fetchFormats()
        }

        let lines = sink.rendered()
        #expect(lines.count == 1, "exactly one event is logged for a transport failure")
        let line = lines.first ?? ""
        #expect(line.contains("event=import.transport.fail"), "line was: \(line)")
        #expect(line.contains("endpoint=/v1/import/formats"), "line was: \(line)")
        #expect(line.contains("errorType=URLError"), "line was: \(line)")
        #expect(line.contains("urlErrorCode=-1001"),
                "the URLError code (-1001 = timedOut) must be logged, line was: \(line)")
    }

    @Test func aCancellationIsNotLoggedAsAFailure() async throws {
        let sink = InMemorySink()
        let log = TankbookLog.makeDefault(sink: sink, deviceId: nil, breadcrumbs: nil)
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport, log: log)
        transport.fail(with: URLError(.cancelled))
        do {
            _ = try await client.fetchFormats()
        } catch ImportClientError.cancelled {
            // expected
        }
        #expect(sink.rendered().isEmpty,
                "a cancellation is not a failure and must produce no warn-level event")
    }

    // MARK: - The source-step STATE each error maps to (the view's offline card)

    @Test func errorToStateOnlyConnectivityIsOffline() {
        // The assertion is on the STATE the source screen renders, not on an
        // error having been thrown - the defect was that a throw happened and
        // the WRONG state followed.
        #expect(ImportClientError.transportUnreachable.formatsOutcome == .offline)
        #expect(ImportClientError.cancelled.formatsOutcome == .noError,
                "a cancellation is not an error state at all")
        #expect(ImportClientError.invalidResponse.formatsOutcome == .contractError,
                "a decode break is a contract error, never offline")
        #expect(ImportClientError.server(status: 500).formatsOutcome == .serverError)
        #expect(ImportClientError.transportFailure.formatsOutcome == .failed,
                "a non-connectivity transport failure is never offline")
        #expect(ImportClientError.client.formatsOutcome == .failed)
    }

    @Test func errorToStateOfflineIsTheOnlyConnectivityCard() async {
        // A genuinely offline transport still lands on the offline card - the
        // legitimate case must not regress (RV.68 keeps the offline state).
        let transport = RV68TestTransport()
        let client = rv68Client(transport: transport)
        transport.failAllRequests()
        do {
            _ = try await client.fetchFormats()
            Issue.record("expected the offline class to throw")
        } catch let error as ImportClientError {
            #expect(error.formatsOutcome == .offline,
                    "notConnectedToInternet must reach the offline card, got \(error)")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
