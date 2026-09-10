import Foundation

// RV.152 - the home-currency change prompt's copy (docs/ERRORS.md -> Vehicle
// detail). In its own file so `L10n.swift` stays under the lint ceiling.

extension L10n {
    /// The prompt title: "Change home currency to USD?". The currency code is
    /// runtime data in the slot and never governs a case.
    static func homeCurrencyChangeTitle(currency: String) -> String {
        String(format: localize("Change home currency to %@?"), currency)
    }

    /// The prompt message. Complete localised sentences joined by a space -
    /// never a fragment (the P1.4 lesson). The pending clause appears only when
    /// the convert would leave rows waiting, so the count is stated before the
    /// user commits; the warning always names the two facts that make the
    /// choice fair: the original receipt amounts are never changed, and there
    /// is no undo.
    static func homeCurrencyChangeMessage(pending: Int) -> String {
        var parts = [localize("Convert the log recalculates each entry from the amount you paid, at that day's rate.")]
        if pending > 0 {
            parts.append(String(localized: "\(pending) entries have no rate for their date and will show as pending until one arrives."))
        }
        parts.append(localize("Keeping the entries as they are leaves them in their currency; totals then show per-currency subtotals, not one figure."))
        parts.append(localize("The original receipt amounts are never changed, and this can't be undone."))
        return parts.joined(separator: " ")
    }
}
