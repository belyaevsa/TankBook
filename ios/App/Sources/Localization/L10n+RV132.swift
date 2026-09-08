import Foundation

/// RV.132's additions, in their own file so `L10n.swift` stays under the lint
/// ceiling (700) - the same `L10n+` split as `L10n+RV111`, `L10n+RV106` etc.
/// Every string here is one full localised phrase per language, never
/// concatenation (the P1.4 lesson), with real RU plural rules for any count.
extension L10n {
    /// The F9 footnote's in-flight acknowledgement (RV.132, docs/ERRORS.md ->
    /// Home): while a user-initiated "Check for rates" demand is on the wire,
    /// the footnote's action is replaced by this line - the tap is acknowledged
    /// IMMEDIATELY, before the network resolves, so a slow provider never reads
    /// as a dead button.
    static var checkingForRates: String {
        localize("Checking for rates…")
    }

    /// The transient result toast when the demand drain converted rows: "2
    /// entries converted". Real plural rules per language (RU three forms:
    /// запись конвертирована / записи конвертированы / записей конвертировано)
    /// via the String Catalog's "%lld entries converted" plural variations.
    static func convertedEntries(_ count: Int) -> String {
        String(localized: "\(count) entries converted")
    }

    /// The transient result toast when a demand drain found no rate-pending row
    /// at all - the tap raced a silent fill, or nothing was ever waiting. It
    /// must read as an outcome, distinct from "filled" and from "the provider
    /// had none" (which the footnote's dead-end copy carries, RV.111).
    static var ratesUpToDate: String {
        localize("Rates are up to date")
    }
}
