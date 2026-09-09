import Foundation

// PJ.28 + RV.149 the receipt-photo-lost report (docs/ERRORS.md -> Service &
// expenses, PJ.28 row; -> Confirm, RV.149 row). One full localised phrase
// shared by every surface whose save could not keep a receipt photo - the
// expense save (PJ.28) and the fill-up save (RV.149) - because one situation
// must meet one sentence, never a near-identical second string that drifts in
// wording and in RU. In its own file so the L10n enum body and the L10n.swift
// file both stay within the lint budget - the L10n+X convention.

extension L10n {
    /// The toast after a scanned entry saved while its receipt photo could not
    /// be kept: the entry is on disk, the photo is not, and the message names
    /// what happened and the next step (hard rules 7 and 8, never a silent drop
    /// and never a blocked save). One full localised phrase per language - RU
    /// word order differs, so no composition. "Entry" is deliberate: the same
    /// sentence must read correctly for a fill-up and for an expense.
    static var receiptNotSavedMessage: String {
        localize("No space to keep the receipt photo – the entry was saved without it. Free up space and re-scan it.")
    }
}
