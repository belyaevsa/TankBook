import Foundation

/// RV.103's additions, in their own file so `L10n.swift` stays under the lint
/// ceiling (700) - the same `L10n+` split as `L10n+RV106`, `L10n+RV71` etc.
extension L10n {
    /// "Show N older entries" - the load-more affordance past Home's preview
    /// (hard rule 7: the visible log ends where the data does not, and says so).
    /// Real plural rules per language via the String Catalog's "%lld older
    /// entries" variations.
    static func olderEntries(_ count: Int) -> String {
        String(localized: "\(count) older entries")
    }
}
