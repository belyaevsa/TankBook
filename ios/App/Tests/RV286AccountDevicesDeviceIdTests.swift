import Foundation
import os
import TankbookCore
import XCTest
@testable import Tankbook

/// RV.286 - deleting the account clears the credentials but must keep the
/// per-install `deviceId`, so the sign-in that follows re-attaches this
/// install's device row instead of minting a new one (docs/SECURITY.md line 30;
/// docs/SYNC.md "Account deletion"). The core store's own survival test lives in
/// the package bundle; this drives the app's `AccountDevicesModel.deleteAccount`
/// seam that calls `clear()`.
@MainActor
final class RV286AccountDevicesDeviceIdTests: XCTestCase {

    private final class StubTransport: TankbookHTTPTransport, @unchecked Sendable {
        func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
            TankbookHTTPResponse(status: 204)
        }
    }

    private final class StubTokenProvider: AuthorizationTokenProvider, @unchecked Sendable {
        func token() -> String? { "test-token" }
    }

    private final class StubSessionStore: SessionStore, @unchecked Sendable {
        private struct State {
            var session: AuthSession?
            var deviceId: String?
        }

        private let lock = OSAllocatedUnfairLock(initialState: State())

        func load() throws -> AuthSession? { lock.withLock { $0.session } }

        func save(_ session: AuthSession) throws {
            lock.withLock {
                $0.session = session
                $0.deviceId = session.deviceId
            }
        }

        func clear() throws { lock.withLock { $0.session = nil } }
        func deviceId() throws -> String? { lock.withLock { $0.deviceId } }
        func forgetDevice() throws { lock.withLock { $0.deviceId = nil } }
        func setAuthExpired(_ expired: Bool) throws {}
        func isAuthExpired() throws -> Bool { false }
        func setDeviceRevoked(_ revoked: Bool) throws {}
        func isDeviceRevoked() throws -> Bool { false }
    }

    func testDeleteAccountKeepsTheDeviceId() async throws {
        let store = StubSessionStore()
        try store.save(AuthSession(accessToken: "at", refreshToken: "rt",
                                   accountId: "acc", deviceId: "dev-286", provider: .apple))
        let client = AccountClient(
            httpClient: TankbookHTTPClient(transport: StubTransport(),
                                           tokenProvider: StubTokenProvider()),
            director: ConfigTransportDirector(
                baseURL: { URL(string: "https://api.tankbook.live")! },
                report: { _ in }))
        let model = AccountDevicesModel(client: client, sessionStore: store)

        let deleted = await model.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertNil(try store.load(), "the credentials are gone after deletion")
        XCTAssertEqual(try store.deviceId(), "dev-286",
                       "the per-install deviceId survives account deletion (docs/SECURITY.md)")
    }
}
