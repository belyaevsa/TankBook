import Foundation
import Security

/// The production rollback floor, stored as a Keychain generic-password item
/// with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// (docs/CONFIG.md -> "Rollback floor in the Keychain", docs/SECURITY.md).
///
/// Kept deliberately thin: a single item, two operations, no parsing beyond an
/// integer. The unit tests use an in-memory double instead, because a plain
/// `swift test` process has no Keychain entitlements; this implementation is
/// exercised on a device, not by the test suite.
public struct KeychainConfigRollbackFloor: ConfigRollbackFloorStoring {
    private let service: String
    private let account: String

    public init(service: String = "live.belyaev.tankbook.config", account: String = "rollback-floor") {
        self.service = service
        self.account = account
    }

    public func highestSeenVersion() -> Int? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              let version = Int(text) else {
            return nil
        }
        return version
    }

    public func record(version: Int) {
        let data = Data(String(version).utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data

        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
