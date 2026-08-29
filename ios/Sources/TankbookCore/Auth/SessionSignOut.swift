import Foundation

/// The sign-out operation (PR.2, docs/SECURITY.md -> the sign-out test). Two
/// steps, in this order, with the second unconditional:
///
/// 1. **Revoke server-side** (`DELETE /auth/session`) - best-effort. A
///    handed-over or sold phone must never keep a 90-day refresh chain valid on
///    the server just because this request failed.
/// 2. **Clear the Keychain** - always, even when the revoke throws (offline
///    sign-out must still sign out locally - hard rule 1). Local data stays
///    local in every case.
///
/// The `RemoteAuthService.signOut` call carries the stored bearer; the clear
/// runs regardless of its outcome.
public struct SessionSignOut: Sendable {
    public let authService: any AuthService
    public let sessionStore: any SessionStore

    public init(authService: any AuthService, sessionStore: any SessionStore) {
        self.authService = authService
        self.sessionStore = sessionStore
    }

    public func signOut() async {
        let session = try? sessionStore.load()
        if let session {
            try? await authService.signOut(session)
        }
        try? sessionStore.clear()
    }
}
