import Foundation
import os
import Testing
@testable import TankbookCore

// PR.3a: the real health prober (docs/CONFIG.md -> "Health gate before
// adoption"). Probes GET {base}/health and returns true only on a 2xx. The
// gate a newly received apiBaseUrl must pass before promotion; any transport
// error or non-2xx is a failed probe.

private final class HealthRecordingTransport: TankbookHTTPTransport, @unchecked Sendable {
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

private struct HealthNilTokenProvider: AuthorizationTokenProvider, Sendable {
    func token() -> String? { nil }
}

@Suite("RemoteHealthProber (PR.3a)")
struct RemoteHealthProberTests {

    @Test func probeReturnsTrueOnA2xx() async {
        let transport = HealthRecordingTransport()
        transport.script([TankbookHTTPResponse(status: 200)])
        let prober = RemoteHealthProber(client: TankbookHTTPClient(
            transport: transport,
            tokenProvider: HealthNilTokenProvider()
        ))

        let result = await prober.probe(baseURL: URL(string: "https://api.tankbook.live")!)

        #expect(result)
        #expect(transport.receivedRequests().first?.url == URL(string: "https://api.tankbook.live/health")!)
    }

    @Test func probeReturnsFalseOnANon2xx() async {
        let transport = HealthRecordingTransport()
        transport.script([TankbookHTTPResponse(status: 503)])
        let prober = RemoteHealthProber(client: TankbookHTTPClient(
            transport: transport,
            tokenProvider: HealthNilTokenProvider()
        ))

        let result = await prober.probe(baseURL: URL(string: "https://api.tankbook.live")!)

        #expect(!result, "a 503 must not pass the health gate")
    }

    @Test func probeReturnsFalseOnATransportError() async {
        struct FailingTransport: TankbookHTTPTransport {
            func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
                throw ConfigStoreError.bundledUnavailable
            }
        }
        let prober = RemoteHealthProber(client: TankbookHTTPClient(
            transport: FailingTransport(),
            tokenProvider: HealthNilTokenProvider()
        ))

        let result = await prober.probe(baseURL: URL(string: "https://api.tankbook.live")!)

        #expect(!result, "an unreachable host must fail the health gate")
    }
}
