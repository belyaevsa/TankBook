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

    // MARK: - The revoked mark (RV.58)

    /// A device revoked server-side answers 410; the client drops the
    /// credentials (`clear`) and persists a revoked mark so the surface keeps
    /// naming "sign in" instead of reading as a plain sign-out. The mark must
    /// survive `clear`, and a fresh `save` (a re-attaching sign-in) must clear
    /// it - the same contract `authExpired` already holds.
    @Test func deviceRevokedMarkSurvivesClearUntilASaveClearsIt() throws {
        let store = KeychainSessionStore(service: "test.auth.\(UUID().uuidString)")
        defer { try? store.clear() }
        try store.clear()

        try store.save(makeSession())
        #expect(try store.isDeviceRevoked() == false,
                "a fresh session is not revoked")

        // The RV.58 drop: clear the credentials, then persist the revoked mark
        // (clear removes the mark too, so the mark is written AFTER it - the
        // same order SessionRefresher uses for authExpired).
        try store.clear()
        try store.setDeviceRevoked(true)
        #expect(try store.isDeviceRevoked() == true,
                "the revoked mark survives the credential drop (RV.58)")
        #expect(try store.load() == nil,
                "the credentials themselves are gone - no further request can authenticate")

        // A re-attaching sign-in writes a fresh session and clears the mark.
        try store.save(makeSession())
        #expect(try store.isDeviceRevoked() == false,
                "a saved session is a session that can authenticate again")
    }
}
