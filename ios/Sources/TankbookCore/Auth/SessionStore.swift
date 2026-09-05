import Foundation

/// Where the auth session lives (docs/SECURITY.md -> the storage table). The
/// real implementation is the Keychain; unit tests use an in-memory double for
/// anything that is not about the Keychain itself, and a Keychain-backed test
/// for the accessibility attribute.
public protocol SessionStore: Sendable {
    /// The stored session, or nil when signed out.
    func load() throws -> AuthSession?
    /// Persists a session. A second save replaces the previous one. Saving
    /// clears any `authExpired` mark - a fresh sign-in or a successful refresh
    /// means the session can authenticate again.
    func save(_ session: AuthSession) throws
    /// Removes every stored credential (sign-out; docs/SECURITY.md -> the
    /// sign-out test: the local database is untouched, only sync stops).
    func clear() throws
    /// Marks the session as having failed authentication (a rejected refresh).
    /// A marked session must not arm the cloud gateway (RV.26) and reads as
    /// "session expired - sign in again", never as an ordinary sign-out.
    func setAuthExpired(_ expired: Bool) throws
    /// Whether the last session's refresh was rejected and the user must sign
    /// in again. Survives `clear` so the "expired" distinction is kept even
    /// after the credentials themselves are removed.
    func isAuthExpired() throws -> Bool
    /// Marks the device as revoked server-side (a 410 - RV.58). A revoked
    /// device's tokens are dropped (`clear`) and this mark survives it, so the
    /// surface keeps naming "sign in" across relaunches instead of reading as
    /// an ordinary sign-out. A fresh `save` (a re-attaching sign-in) clears it.
    func setDeviceRevoked(_ revoked: Bool) throws
    /// Whether the last session's device was revoked (410). Survives `clear`
    /// exactly like the `authExpired` mark, for the same reason.
    func isDeviceRevoked() throws -> Bool
}
