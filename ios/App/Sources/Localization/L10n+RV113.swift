import Foundation

/// RV.113's addition, in its own file so `L10n.swift` stays under the lint
/// ceiling (700) - the same `L10n+` split as `L10n+RV111`, `L10n+RV106`,
/// `L10n+RV71`, `L10n+Language` etc.
extension L10n {
    /// "This file has no currency column, so we'll use your pick for every row."
    /// (RV.113 - the file cannot say, so the wizard asks; hard rule 13).
    static var currencyQuestionSubtitle: String {
        localize("This file has no currency column, so we'll use your pick for every row.")
    }

    /// "The file says USD. Change it if that's wrong." (RV.263 - a currency the
    /// file declares is a correctable default, never a fact; hard rule 13). A
    /// whole localised phrase per language, never a concatenation, so the RU
    /// sentence can order the code its own way (docs/LOCALIZATION.md).
    static func currencyDeclaredSubtitle(_ code: String) -> String {
        String(localized: "The file says \(code). Change it if that's wrong.")
    }
}
