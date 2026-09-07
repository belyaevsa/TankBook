import Foundation

/// RV.111's addition, in its own file so `L10n.swift` stays under the lint
/// ceiling (700) - the same `L10n+` split as `L10n+RV106`, `L10n+RV71`,
/// `L10n+Language` etc.
extension L10n {
    /// The F9 footnote's dead-end next step (docs/ERRORS.md -> Home): the
    /// demand pass already asked for these rows' dates and the provider had no
    /// rate for them, so the way out is the MANUAL rate on each entry (hard
    /// rule 13) - never a promise that another check will help. One full
    /// localised phrase per language (never concatenation); the count above
    /// keeps its own plural key, `pendingRates`.
    static var pendingRatesDeadEnd: String {
        localize("No rate exists for these dates. Add a manual rate to each entry.")
    }
}
