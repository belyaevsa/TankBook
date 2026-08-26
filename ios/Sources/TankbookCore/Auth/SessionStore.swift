import Foundation

/// Where the auth session lives (docs/SECURITY.md -> the storage table). The
/// real implementation is the Keychain; unit tests use an in-memory double for
/// anything that is not about the Keychain itself, and a Keychain-backed test
/// for the accessibility attribute.
public protocol SessionStore: Sendable {
    /// The stored session, or nil when signed out.
    func load() throws -> AuthSession?
    /// Persists a session. A second save replaces the previous one.
    func save(_ session: AuthSession) throws
    /// Removes every stored credential (sign-out; docs/SECURITY.md -> the
    /// sign-out test: the local database is untouched, only sync stops).
    func clear() throws
}
