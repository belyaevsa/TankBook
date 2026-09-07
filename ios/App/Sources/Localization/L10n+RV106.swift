import Foundation

/// RV.106's additions, in their own file so `L10n.swift` stays under the lint
/// ceiling (700) - the same `L10n+` split as `L10n+RV71`, `L10n+Language` etc.
extension L10n {
    /// "Check for rates" - the F9 footnote's next-step action (hard rule 7,
    /// RV.106): re-runs the rate refresh + S8 backfill the next launch would
    /// run, so a user who imported rows while the rate archive was still being
    /// published can ask for the fill now instead of waiting for a relaunch.
    static var checkForRates: String {
        localize("Check for rates")
    }

    /// The "Check for rates" action's accessibility hint - what the tap does,
    /// so a screen-reader user is not guessing at "Check".
    static var checkForRatesHint: String {
        localize("Checks whether rates are available for these entries now")
    }
}
