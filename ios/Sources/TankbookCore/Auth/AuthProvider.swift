import Foundation

/// The two sign-in identity providers (docs/API.md -> Auth). Apple and Google
/// identities are **distinct accounts**; v1 ships no account linking, so the
/// client is responsible for the wrong-provider UX (docs/JOURNEYS.md J11a) and
/// the backend simply maps whichever token arrives to its own account.
public enum AuthProvider: String, Sendable, Codable, CaseIterable {
    case apple
    case google
}
