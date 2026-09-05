import Foundation
import os
@testable import TankbookCore

// Shared auth test doubles. `InMemorySessionStore` is the `SessionStore` double
// for anything not about the Keychain itself; `RecordingTransport` records the
// exact requests a `RemoteAuthService` hands to its transport, so the tests
// assert what was actually sent rather than a mock's opinion (the trap named in
// the P4.4 brief).

/// An in-memory `SessionStore`. Not thread-safe by itself; the lock makes it a
/// valid `Sendable` double for the concurrent auth client.
final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private struct State {
        var session: AuthSession?
        var authExpired = false
        var deviceRevoked = false
        var loadCount = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    init(session: AuthSession? = nil) {
        if let session { lock.withLock { $0.session = session } }
    }

    func load() throws -> AuthSession? {
        lock.withLock { $0.loadCount += 1 }
        return lock.withLock { $0.session }
    }

    func save(_ session: AuthSession) throws {
        lock.withLock {
            $0.session = session
            $0.authExpired = false
            $0.deviceRevoked = false
        }
    }

    func clear() throws {
        lock.withLock {
            $0.session = nil
            $0.authExpired = false
            $0.deviceRevoked = false
        }
    }

    func setAuthExpired(_ expired: Bool) throws {
        lock.withLock { $0.authExpired = expired }
    }

    func isAuthExpired() throws -> Bool {
        lock.withLock { $0.authExpired }
    }

    func setDeviceRevoked(_ revoked: Bool) throws {
        lock.withLock { $0.deviceRevoked = revoked }
    }

    func isDeviceRevoked() throws -> Bool {
        lock.withLock { $0.deviceRevoked }
    }

    var loadCount: Int { lock.withLock { $0.loadCount } }
}

/// Records the requests it receives and returns scripted responses, exactly
/// like the client tests' transport double.
final class AuthRecordingTransport: TankbookHTTPTransport, @unchecked Sendable {
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
