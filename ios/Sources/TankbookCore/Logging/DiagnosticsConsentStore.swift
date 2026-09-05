import Foundation

/// The once-asked "Attach diagnostics" opt-in (docs/LOGGING.md §5: never silent,
/// never automatic, never on by default). Default OFF, persisted, and changeable
/// afterwards (hard rule 13: a value the user set is theirs). It is the
/// load-bearing half of the diagnostics export: the preview is unreachable until
/// this is on, exactly as the feedback composer's consent gates its queue.
///
/// The value is read from `UserDefaults` on every access and written on every
/// change - never cached in memory - so a second instance over the same store
/// sees the persisted value (a persistence bug must be visible, not assumed
/// away). Same shape as `FeedbackConsentStore`.
public final class DiagnosticsConsentStore: @unchecked Sendable {
    public static let defaultKey = "tankbook.diagnostics.consent"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = DiagnosticsConsentStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Default off: a fresh install has not opted in.
    public var hasConsented: Bool {
        defaults.bool(forKey: key)
    }

    public func setConsented(_ consented: Bool) {
        defaults.set(consented, forKey: key)
    }

    /// Removes the stored value, returning the store to its fresh-install state
    /// (the default governs again). Test/screenshot seam, and the reset half of
    /// "the value is theirs, changeable afterwards" (hard rule 13 is served by
    /// `setConsented`, which the UI uses; this exists for the DEBUG reset).
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
