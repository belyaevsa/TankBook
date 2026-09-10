import Foundation

/// RV.116's addition, in its own file so `L10n.swift` stays under the lint
/// ceiling - the same `L10n+` split as `L10n+RV113`, `L10n+RV111` etc.
extension L10n {
    /// "250 rows carry a value" - how many rows of the imported file carried a
    /// value in one unsupported column (RV.116). The count is the whole value
    /// of the notice: "driver is not imported" is trivia, "250 rows carry a
    /// driver" is a decision. Real plural rules per language.
    static func unsupportedColumnRows(_ count: Int) -> String {
        String(localized: "\(count) rows carry a value")
    }
}
