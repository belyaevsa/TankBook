import Foundation

/// Obtains a provider identity token (docs/SECURITY.md -> "the client's job is
/// to obtain it and hand it over"). Injected so the sign-in flow is testable
/// without a real Apple ID or Google account: the production implementation
/// drives `AuthenticationServices` for Apple, while unit tests and UI-test
/// seeds use a double that returns a canned identity.
///
/// Deliberately `@MainActor` (not `Sendable`): the real implementation presents
/// system UI (`ASAuthorizationController`), so it runs on the main actor; the
/// `SignInFlow` that owns it is `@MainActor` too.
@MainActor
public protocol IDTokenProvider {
    /// Runs the platform sign-in UI for `provider` and returns the identity the
    /// user consented to. Throws when the user declines or the flow fails - the
    /// caller then returns to a working app, never to a wall (hard rule 1).
    func signIn(provider: AuthProvider) async throws -> ProviderIdentity
}
