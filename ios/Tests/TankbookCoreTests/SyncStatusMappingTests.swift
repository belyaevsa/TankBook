import Foundation
import os
import Testing
@testable import TankbookCore

// P6.11 - how a shipped client reads a server that has moved ahead of it.
//
// There is no Pro tier: every user has full access. So the only way a client
// meets a tier or capability gate is a server upgraded past it, and the honest
// reading is "this app is out of date", never "buy something" (hard rule 7:
// monetization appears in no error surface but the car-limit sheet).
//
// The defect these tests pin: before P6.11, `402`, `429` and every unknown 4xx
// fell into `default` and were reported as `.invalidResponse` - "the body could
// not be decoded" - about a response that decoded perfectly well and simply said
// no. A generic failure message for a specific refusal is what JOURNEYS F7
// forbids, and there was no test on this mapping at all, which is why it
// survived.

private final class StatusTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<TankbookHTTPResponse>

    init(_ response: TankbookHTTPResponse) {
        lock = OSAllocatedUnfairLock(initialState: response)
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { $0 }
    }
}

private struct NoToken: AuthorizationTokenProvider {
    func token() -> String? { "test-token" }
}

private func transport(status: Int, headers: [String: String] = [:]) -> RemoteSyncTransport {
    RemoteSyncTransport(
        baseURL: URL(string: "https://api.tankbook.app")!,
        transport: StatusTransport(
            TankbookHTTPResponse(status: status, headers: headers, body: Data("{}".utf8))
        ),
        tokenProvider: NoToken()
    )
}

private func pullError(status: Int, headers: [String: String] = [:]) async -> SyncServerError? {
    do {
        _ = try await transport(status: status, headers: headers).pull(since: 0, limit: 10)
        return nil
    } catch let error as SyncServerError {
        return error
    } catch {
        return nil
    }
}

@Suite("Server status mapping (P6.11)")
struct SyncStatusMappingTests {

    /// Each gated status maps to its OWN outcome. The mutation that matters is
    /// collapsing any one of these into another case - a suite that only checks
    /// "it threw" cannot see that, which is how the old mapping stayed wrong.
    @Test("402, 429, 426 and 410 each map to a distinct error")
    func gatedStatusesAreDistinct() async {
        #expect(await pullError(status: 402) == .tierRefused)
        #expect(await pullError(status: 426) == .upgradeRequired)
        #expect(await pullError(status: 410) == .deviceRevoked)
        #expect(await pullError(status: 429) == .rateLimited(retryAfterSeconds: nil))

        // ...and none of them is the transport case or the decode case, which is
        // the specific lie this task exists to remove.
        for status in [402, 426, 410, 429] {
            let error = await pullError(status: status)
            #expect(error != .transportUnavailable, "\(status) must not read as an outage")
            #expect(error != .invalidResponse, "\(status) must not read as an undecodable body")
        }
    }

    /// The server's own hint is carried through rather than guessed at.
    @Test("429 carries Retry-After when the server sends one")
    func rateLimitCarriesRetryAfter() async {
        #expect(await pullError(status: 429, headers: ["Retry-After": "120"])
                == .rateLimited(retryAfterSeconds: 120))
        // A malformed or absent header degrades to nil - never to a made-up wait.
        #expect(await pullError(status: 429, headers: ["Retry-After": "soon"])
                == .rateLimited(retryAfterSeconds: nil))
    }

    /// The forward-compatibility case: a gate this client version has never
    /// heard of. It must report what it is - a refusal carrying its status - so
    /// the surface can say something true, rather than "could not decode".
    @Test("an unknown 4xx from a newer server is a refusal, not a decode failure")
    func unknownGateIsHonest() async {
        #expect(await pullError(status: 403) == .refused(status: 403))
        #expect(await pullError(status: 451) == .refused(status: 451))
        #expect(await pullError(status: 418) == .refused(status: 418))
        for status in [403, 451, 418] {
            #expect(await pullError(status: status) != .invalidResponse)
            #expect(await pullError(status: status) != .transportUnavailable)
        }
    }

    /// A 5xx is the server having a problem, which is S7: it resolves itself,
    /// rows return to dirty, and it must NOT be reported as a refusal that asks
    /// the user to update an app that is perfectly current.
    @Test("5xx stays the transport case - an outage is not a refusal")
    func serverErrorIsAnOutage() async {
        #expect(await pullError(status: 500) == .transportUnavailable)
        #expect(await pullError(status: 503) == .transportUnavailable)
        #expect(await pullError(status: 500) != .refused(status: 500))
    }
}
