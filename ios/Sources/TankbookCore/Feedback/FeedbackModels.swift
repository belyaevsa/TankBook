import Foundation

// The feedback wire models (docs/API.md -> Feedback). Built against the
// documented contract exactly as every other client row is built against a stub
// transport: `POST /feedback` is specified and the server half is filed
// separately as PJ.20a.

/// The feedback category the user picks. The wire sends the raw string; the
/// three cases are the only values the documented contract accepts.
public enum FeedbackCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case feature
    case problem
    case other
}

/// The `POST /feedback` body (docs/API.md -> Feedback). `deviceModel` rides only
/// with the user's toggle - the contract names it optional and the composer
/// attaches it only when the toggle is on. `replyTo` is an optional contact
/// address. `text` is capped at 4 KB by the composer (docs/API.md: "text ≤ 4 KB").
public struct FeedbackPayload: Codable, Sendable, Equatable, Hashable {
    public let category: FeedbackCategory
    public let text: String
    public let appVersion: String
    public let deviceModel: String?
    public let replyTo: String?

    public static let maxTextLength = 4_000

    public init(category: FeedbackCategory, text: String, appVersion: String,
                deviceModel: String?, replyTo: String?) {
        self.category = category
        self.text = String(text.prefix(Self.maxTextLength))
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.replyTo = replyTo
    }
}
