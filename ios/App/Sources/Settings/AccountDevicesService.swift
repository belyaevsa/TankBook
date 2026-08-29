import Foundation
import os
import TankbookCore

/// Builds the Account & devices screen's model over the app's one HTTP client,
/// with a DEBUG/test seam: launch arguments can install a stub transport
/// serving the canned device list (docs/TESTING.md), force the offline state,
/// or make a revoke/delete answer 401 - so UI tests and screenshots drive the
/// screen without a server. Production never passes those arguments.
@MainActor
enum AccountDevicesService {

    static func makeModel(sessionStore: KeychainSessionStore = KeychainSessionStore()) -> AccountDevicesModel {
        let arguments = ProcessInfo.processInfo.arguments
        let transport: any TankbookHTTPTransport
        if arguments.contains("-accountTransportOffline") {
            transport = FailingAccountTransport()
        } else if let stub = AccountStubTransport(launchArguments: arguments) {
            transport = stub
        } else {
            transport = URLSessionTransport()
        }
        let client = AccountClient(
            httpClient: TankbookHTTPClient(
                transport: transport,
                tokenProvider: KeychainTokenProvider(sessionStore: sessionStore),
                refresher: AppSessionRefresher.shared),
            director: AppConfigStore.shared.director)
        return AccountDevicesModel(client: client, sessionStore: sessionStore)
    }
}

/// A DEBUG/test transport that answers the account endpoints with canned JSON.
/// `-accountStubDevices <name>` loads `account-devices-<name>.json` from the
/// bundle (see the fixture files in App/Resources); `-accountStubRevoke401`
/// makes a revoke answer 401 (the session-expired path). A successful revoke
/// marks that device revoked in the stub's in-memory state, so the next
/// `GET /devices` reflects it - the screen's "Signed out" state is real, not
/// asserted against a static fixture.
struct AccountStubTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let devicesName: String?
    private let revoke401: Bool
    private let lock = OSAllocatedUnfairLock(initialState: Set<String>())

    init?(launchArguments: [String]) {
        devicesName = Self.value(for: "-accountStubDevices", in: launchArguments)
        revoke401 = launchArguments.contains("-accountStubRevoke401")
        if devicesName == nil && !revoke401 { return nil }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let path = request.url.path
        if path.hasPrefix("/v1/account/devices"), request.method == "GET", let devicesName {
            let revoked = lock.withLock { $0 }
            return Self.resource("account-devices-\(devicesName)", revoked: revoked)
        }
        if path.hasPrefix("/v1/account/devices/"), request.method == "DELETE" {
            if revoke401 { return TankbookHTTPResponse(status: 401) }
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            lock.withLock { $0.insert(id) }
            return TankbookHTTPResponse(status: 204)
        }
        if path == "/v1/account", request.method == "DELETE" {
            return TankbookHTTPResponse(status: 204)
        }
        return TankbookHTTPResponse(status: 404)
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Serves the fixture, flipping `revoked` to true for every device the test
    /// already revoked in this process (the stub is in-memory, exactly like the
    /// app's own state would be after a real revoke + reload).
    private static func resource(_ name: String, revoked: Set<String>) -> TankbookHTTPResponse {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var devices = object["devices"] as? [[String: Any]] else {
            return TankbookHTTPResponse(status: 404)
        }
        for index in devices.indices {
            if let id = devices[index]["id"] as? String, revoked.contains(id) {
                devices[index]["revoked"] = true
            }
        }
        let rewritten = ["devices": devices]
        let body = try? JSONSerialization.data(withJSONObject: rewritten)
        return TankbookHTTPResponse(status: 200, body: body)
    }
}

/// The offline seam: every request fails like a lost connection (F3/S7 - being
/// offline is never an error, the screen says so and retries).
struct FailingAccountTransport: TankbookHTTPTransport, @unchecked Sendable {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}
