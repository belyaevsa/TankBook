import Foundation

// The whole-export pick's phrases (RV.93) live in their own extension so the
// main L10n file stays under the repo's lint floors. All full localised
// phrases per language, never concatenation (hard rule 10, docs/LOCALIZATION.md
// - RU word order and declension differ, which is exactly what the plural
// rules here carry).

extension L10n {

    /// "from 6 files · nothing is saved yet" - the source line for a
    /// whole-export pick of several files (RV.93). Full phrase per language,
    /// real plural rules; the count is runtime data sharing the sentence.
    static func fromFilesNothingSaved(count: Int) -> String {
        String(localized: "from \(count) files · nothing is saved yet")
    }

    /// "2 files couldn't be imported" - the whole-export pick's per-file
    /// failures header (RV.93, hard rule 7: the failures are named, never
    /// silent). Plural per language.
    static func someFilesFailed(_ count: Int) -> String {
        String(localized: "\(count) files couldn't be imported")
    }

    /// "Continue with 4 files" - the source step's bar when part of a
    /// whole-export pick failed: the files that parsed go on, the failed ones
    /// stay behind on their cards (RV.93, hard rule 7 - the run survives).
    static func continueWithFiles(_ count: Int) -> String {
        String(localized: "Continue with \(count) files")
    }
}
