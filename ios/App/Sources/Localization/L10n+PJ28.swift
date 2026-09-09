import Foundation

// PJ.28 the scanned Expense save's receipt-photo failure (docs/ERRORS.md ->
// Service & expenses). In its own file so the L10n enum body and the L10n.swift
// file both stay within the lint budget - the L10n+X convention.

extension L10n {
    /// The toast after a scanned expense saved while its receipt photo could
    /// not be kept: the entry is on disk, the photo is not, and the message
    /// names what happened and the next step (hard rules 7 and 8, never a
    /// silent drop and never a blocked save). One full localised phrase per
    /// language - RU word order differs, so no composition.
    static var expenseReceiptNotSavedMessage: String {
        localize("No space to keep the receipt photo – the expense was saved without it. Free up space and re-scan it.")
    }
}
