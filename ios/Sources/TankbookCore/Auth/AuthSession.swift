import Foundation

/// The result of a successful `POST /auth/session` exchange (docs/API.md ->
/// Auth). `accessToken` is a short-lived JWT (~1h); `refreshToken` rotates on
/// every refresh and reuse of a rotated token revokes the chain.
///
/// This value never leaves the device: it is held only in the Keychain
/// (docs/SECURITY.md -> the storage table), and is never logged (hard rule 12).
/// Deliberately **not** `Codable` - the tokens are stored as three separate
/// Keychain items, never serialised into one blob.
public struct AuthSession: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accountId: String
    public let deviceId: String
    public let provider: AuthProvider
    /// Display identity for the Settings account card ("driver@icloud.com").
    /// Nil for a hidden Apple private-relay identity (the provider never handed
    /// an email), in which case the UI falls back to the provider name.
    public let email: String?

    public init(
        accessToken: String,
        refreshToken: String,
        accountId: String,
        deviceId: String,
        provider: AuthProvider,
        email: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.deviceId = deviceId
        self.provider = provider
        self.email = email
    }

    /// A copy with a rotated token pair and every other field unchanged (the
    /// refresh response carries only the two tokens - docs/API.md -> Auth).
    func rotated(accessToken: String, refreshToken: String) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: accountId,
            deviceId: deviceId,
            provider: provider,
            email: email
        )
    }
}

/// What a provider sign-in flow hands the app after the user consents: the
/// verified identity token plus the display identity. The server verifies the
/// token, so the client's only job is to obtain it and hand it over
/// (docs/SECURITY.md -> "the token exchange is verified server-side").
///
/// `email` is display-only (the Restoring screen's "driver@icloud.com" line)
/// and may be nil for a hidden Apple private-relay identity.
public struct ProviderIdentity: Sendable, Equatable {
    public let provider: AuthProvider
    public let idToken: String
    public let email: String?

    public init(provider: AuthProvider, idToken: String, email: String?) {
        self.provider = provider
        self.idToken = idToken
        self.email = email
    }
}
