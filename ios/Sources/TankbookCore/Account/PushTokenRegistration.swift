import Foundation

// MARK: - When the APNs token goes up (PR.20, docs/NOTIFICATIONS.md)

/// The pure decision behind the push-token PUT: send when there is a token and
/// a signed-in account, and the pair (token, account) differs from what was
/// last acknowledged - so a relaunch with an unchanged token sends nothing, a
/// token rotation sends once, and a different account sends again even with
/// the same token (the row is per account-device).
public enum PushTokenRegistration {
    public struct Acknowledged: Codable, Sendable, Equatable {
        public let token: String
        public let accountId: String

        public init(token: String, accountId: String) {
            self.token = token
            self.accountId = accountId
        }
    }

    public static func shouldSend(token: String?, accountId: String?,
                                  acknowledged: Acknowledged?) -> Bool {
        guard let token, !token.isEmpty, let accountId, !accountId.isEmpty else { return false }
        return acknowledged != Acknowledged(token: token, accountId: accountId)
    }

    /// The APNs device token as the server stores it: lowercase hex of the
    /// raw bytes.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
