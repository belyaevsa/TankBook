import Foundation
import Security

/// The Keychain-backed session store, exactly per docs/SECURITY.md -> the
/// storage table:
///
/// | Item | Keychain class | Accessibility |
/// |---|---|---|
/// | Access token (JWT, ~1h) | `kSecClassGenericPassword` | `AfterFirstUnlockThisDeviceOnly` |
/// | Refresh token (rotating) | separate item | same |
/// | `deviceId` | separate item | same |
///
/// **`ThisDeviceOnly` on every item** keeps tokens out of iCloud Keychain and
/// out of backups, which is what makes per-device revocation meaningful
/// (docs/SECURITY.md). `AfterFirstUnlock` keeps them readable to background sync
/// after a reboot while still encrypting them until the first unlock.
///
/// `accountId` and `provider` are identifiers, not secrets, so they are stored
/// in a fourth, non-secret item (same class and accessibility, for consistency)
/// rather than being folded into any of the three credential items. The table's
/// "nothing else" row is about secrets.
public struct KeychainSessionStore: SessionStore {
    private let service: String

    /// The single accessibility class every session item is written with. It is
    /// the whole security property of this type (docs/SECURITY.md -> "Keychain
    /// attribute test: a wrong constant compiles perfectly and fails silently
    /// in the field"), so it lives as one value and is asserted on the write
    /// path (see `itemQuery`).
    public static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    private enum Account {
        static let accessToken = "access-token"
        static let refreshToken = "refresh-token"
        static let deviceId = "device-id"
        static let metadata = "session-metadata"
    }

    public init(service: String = "live.belyaev.tankbook.auth") {
        self.service = service
    }

    // MARK: - SessionStore

    public func load() throws -> AuthSession? {
        guard let accessToken = read(Account.accessToken),
              let refreshToken = read(Account.refreshToken),
              let deviceId = read(Account.deviceId),
              let metadataData = readData(Account.metadata),
              let metadata = try? JSONDecoder().decode(SessionMetadata.self, from: metadataData) else {
            return nil
        }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: metadata.accountId,
            deviceId: deviceId,
            provider: metadata.provider,
            email: metadata.email
        )
    }

    public func save(_ session: AuthSession) throws {
        write(Account.accessToken, session.accessToken)
        write(Account.refreshToken, session.refreshToken)
        write(Account.deviceId, session.deviceId)
        let metadata = SessionMetadata(accountId: session.accountId, provider: session.provider, email: session.email)
        if let data = try? JSONEncoder().encode(metadata) {
            writeData(Account.metadata, data)
        }
    }

    public func clear() throws {
        delete(Account.accessToken)
        delete(Account.refreshToken)
        delete(Account.deviceId)
        delete(Account.metadata)
    }

    // MARK: - The write path, exposed for the enforcement test

    /// Builds the exact query handed to `SecItemAdd`/`SecItemUpdate` for one
    /// item, including the accessibility class and the generic-password class.
    ///
    /// Exposed because macOS cannot read `kSecAttrAccessible` back out of the
    /// Keychain (it returns nil - the attribute only round-trips on iOS), so
    /// the enforcement test asserts the dictionary the store actually writes.
    /// `save` is literally `SecItemAdd(itemQuery(...))`, so asserting the query
    /// is asserting what reaches the Keychain.
    public static func itemQuery(service: String, account: String, value: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: value,
        ]
    }

    // MARK: - Raw Keychain operations

    private func read(_ account: String) -> String? {
        guard let data = readData(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readData(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func write(_ account: String, _ value: String) {
        writeData(account, Data(value.utf8))
    }

    private func writeData(_ account: String, _ data: Data) {
        let addQuery = Self.itemQuery(service: service, account: account, value: data)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess { return }
        // Item already exists: update the value in place, preserving the
        // accessibility class it was created with.
        let update: [String: Any] = [kSecValueData as String: data]
        SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // MARK: - Non-secret metadata

    private struct SessionMetadata: Codable {
        let accountId: String
        let provider: AuthProvider
        let email: String?
    }
}
