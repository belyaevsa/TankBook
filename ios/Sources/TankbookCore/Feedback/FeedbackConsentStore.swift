import Foundation

/// The once-asked "help improve scanning - attach this case" opt-in
/// (docs/ERRORS.md -> About & feedback). Default OFF, persisted, and changeable
/// afterwards (hard rule 13: a value the user set is theirs). It is the
/// load-bearing half of the feedback feature: a case is queued only with consent
/// (`FeedbackQueue`), so the default being off is what makes consent mean
/// something.
///
/// The value is read from `UserDefaults` on every access and written on every
/// change - never cached in memory - so a second instance over the same store
/// sees the persisted value (a persistence bug must be visible, not assumed
/// away).
public final class FeedbackConsentStore: @unchecked Sendable {
    public static let defaultKey = "tankbook.feedback.consent"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = FeedbackConsentStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Default off: a fresh install has not consented.
    public var hasConsented: Bool {
        defaults.bool(forKey: key)
    }

    public func setConsented(_ consented: Bool) {
        defaults.set(consented, forKey: key)
    }
}
