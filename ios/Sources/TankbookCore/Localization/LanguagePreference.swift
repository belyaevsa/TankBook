import Foundation

// MARK: - RV.24 the language decision (docs/TASKS.md RV.24)

/// The single decision behind the Settings language picker (docs/TASKS.md RV.24,
/// the product-owner wording "default from the system setting of the first
/// launch"):
///
/// - **No stored preference means "follow the system".** Nothing is written at
///   first launch, so a user who later changes their phone's language sees the
///   app follow it. Storing the system value at first launch would silently
///   freeze the app against the phone.
/// - **A stored preference wins.** Once the user picks a language in Settings,
///   that value is theirs (hard rule 13) and applies on the next launch through
///   the `AppleLanguages` key.
///
/// This is a pure rule and does not belong inline in a view.
public enum LanguagePreference {
    /// What the app resolves to.
    public enum Resolution: Equatable, Sendable {
        /// Follow the system language - no stored preference exists.
        case followSystem
        /// A stored preference: the language code the user chose.
        case selected(String)
    }

    /// The `AppleLanguages` key iOS reads at launch to override the app
    /// language. The array is ordered by preference; the first element is the
    /// one that applies.
    public static let appleLanguagesKey = "AppleLanguages"

    /// The decision: no stored preference -> follow the system; a stored one
    /// wins. A nil or empty value is treated as "not stored".
    public static func resolve(storedLanguage: String?) -> Resolution {
        guard let code = storedLanguage, !code.isEmpty else {
            return .followSystem
        }
        return .selected(code)
    }

    /// Whether the app is pending a relaunch to apply the stored language choice
    /// (docs/TASKS.md RV.42). **Derived, never stored**: the app is pending a
    /// relaunch exactly while the stored preference differs from the language
    /// actually running (`Bundle.main.preferredLocalizations.first`). A nil or
    /// empty stored value means "follow the system" and is never pending - a
    /// user who never overrode is not waiting for anything. It self-clears on
    /// the next launch (the running language then matches the stored one) with
    /// nothing to reset, which is what makes it correct: no bookkeeping can
    /// drift out of sync with reality.
    public static func isPendingRestart(storedLanguage: String?,
                                        runningLanguage: String?) -> Bool {
        guard let stored = storedLanguage, !stored.isEmpty else { return false }
        guard let running = runningLanguage, !running.isEmpty else { return false }
        return stored != running
    }
}

/// Persistence for the user's language choice (docs/TASKS.md RV.24). Two keys:
///
/// - `storedLanguageKey` records the user's *choice* and is the readback: nil
///   means "follow the system". It is app-owned so the read is never polluted
///   by the system's own global `AppleLanguages` (which is exactly what a
///   `UserDefaults` read of `AppleLanguages` would return on a fresh install -
///   the phone's language - and would make "follow the system" indistinguishable
///   from "the system happens to be English").
/// - `AppleLanguages` is written alongside the choice because iOS reads it at
///   launch to apply the override. It is the effect, never the readback.
///
/// Reads the defaults on every access and writes on every change, never cached
/// in memory - the same shape as `FeedbackConsentStore`.
public final class LanguagePreferenceStore: @unchecked Sendable {
    /// The app-owned readback key: the chosen code, absent = follow the system.
    public static let storedLanguageKey = "tankbook.language.override"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored choice, nil when the user has not overridden (follow the
    /// system).
    public var storedLanguage: String? {
        defaults.string(forKey: Self.storedLanguageKey)
    }

    /// The resolved choice: nil when there is no stored preference (follow the
    /// system), else the chosen language code.
    public var selectedLanguage: String? {
        switch LanguagePreference.resolve(storedLanguage: storedLanguage) {
        case .followSystem: return nil
        case .selected(let code): return code
        }
    }

    /// Writes the choice; applies on the next launch. `AppleLanguages` carries
    /// the launch effect, `storedLanguageKey` carries the readback.
    public func select(_ languageCode: String) {
        defaults.set(languageCode, forKey: Self.storedLanguageKey)
        defaults.set([languageCode], forKey: LanguagePreference.appleLanguagesKey)
    }

    /// Removes the choice so the app follows the system again - a distinct
    /// state from "the system language happens to be English" (docs/TASKS.md
    /// RV.24).
    public func followSystem() {
        defaults.removeObject(forKey: Self.storedLanguageKey)
        defaults.removeObject(forKey: LanguagePreference.appleLanguagesKey)
    }
}
