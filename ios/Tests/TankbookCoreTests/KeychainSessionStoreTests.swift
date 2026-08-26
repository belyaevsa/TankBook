import Foundation
import Security
import Testing
@testable import TankbookCore

// P4.4: the Keychain session store (docs/SECURITY.md -> the storage table). The
// security property is the accessibility class - a wrong constant compiles
// perfectly and fails silently in the field - so the tests assert the exact
// dictionary the store hands to `SecItemAdd`, not merely that a value round
// trips. macOS cannot read `kSecAttrAccessible` back out (it returns nil - see
// the probe in the P4.4 session), which is exactly why the assertion must be on
// the write path.
@Suite("KeychainSessionStore (P4.4)")
struct KeychainSessionStoreTests {

    private func makeSession(provider: AuthProvider = .apple) -> AuthSession {
        AuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accountId: "account-1",
            deviceId: "device-1",
            provider: provider
        )
    }

    // MARK: - The accessibility attribute

    /// The item query the store writes is `kSecClassGenericPassword` with
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `save` is literally
    /// `SecItemAdd(itemQuery(...))`, so this asserts what reaches the Keychain.
    @Test func itemQueryCarriesAfterFirstUnlockThisDeviceOnly() {
        let query = KeychainSessionStore.itemQuery(
            service: "s", account: "a", value: Data("v".utf8))

        #expect((query[kSecClass as String] as? String) == (kSecClassGenericPassword as String))
        #expect((query[kSecAttrAccessible as String] as? String)
                == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String),
                "every session item must be AfterFirstUnlockThisDeviceOnly (docs/SECURITY.md)")
    }

    @Test func theStoreAccessibilityConstantIsAfterFirstUnlockThisDeviceOnly() {
        #expect(KeychainSessionStore.accessibility == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    // MARK: - Round trip and sign-out

    /// A saved session loads back intact and `clear` removes everything - the
    /// sign-out contract (docs/SECURITY.md: "signing out removes every Keychain
    /// item and leaves the local database intact").
    @Test func roundTripThroughTheRealKeychainAndClearRemovesEverything() throws {
        let store = KeychainSessionStore(service: "test.auth.\(UUID().uuidString)")
        defer { try? store.clear() }
        try store.clear()

        #expect(try store.load() == nil)

        let session = makeSession()
        try store.save(session)
        #expect(try store.load() == session)

        try store.clear()
        #expect(try store.load() == nil)
    }

    /// Saving twice replaces the session rather than appending or failing - the
    /// update path (`SecItemUpdate` after `errSecDuplicateItem`) works.
    @Test func aSecondSaveReplacesTheSession() throws {
        let store = KeychainSessionStore(service: "test.auth.\(UUID().uuidString)")
        defer { try? store.clear() }
        try store.clear()

        try store.save(makeSession(provider: .apple))
        try store.save(makeSession(provider: .google))

        #expect(try store.load()?.provider == .google)
    }
}
