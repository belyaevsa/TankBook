import Foundation

// MARK: - PJ.48 the blank-fields-only attach merge (docs/ERRORS.md -> Edit
// entry, the two new rows; docs/JOURNEYS.md J3b "Later").
//
// When a receipt is attached to an entry the user TYPED, the OCR may offer
// pre-fills for fields the typed entry left BLANK, and for those only. A typed
// value is a fact and is never overwritten (hard rule 13); an OCR reading that
// disagrees with what was typed produces no amber, no dialog, nothing - the
// typed value wins silently and the photo is kept either way (ERRORS.md:126).
//
// This is the guarantee the whole row is about, and it lives in core for the
// same reason `AppTabBar`'s arithmetic had to (the P3.7 lesson): a
// blank-fields-only rule pinned only at L4 is "verified by looking at one
// device". A pure function taking (typed entry, OCR result) and returning
// (suggestions for blank fields only) is trivially testable, and the views only
// call it.

/// The fields a freshly-attached receipt's OCR may suggest pre-fills for, on an
/// entry the user typed.
public enum ReceiptAttachMerge {

    /// The subset of the OCR result that may be offered as a pre-fill: fields
    /// the typed entry left blank AND the OCR resolved. Every other resolved
    /// field is deliberately dropped - it disagrees with a typed value, and a
    /// typed value wins silently (hard rule 13). Returns nothing for a fully
    /// typed entry no matter what the OCR read.
    ///
    /// "Blank" on a `FillUp` is exactly the absence the schema can represent:
    /// `money == nil` (the fill recorded no amount, so both total and currency
    /// are blank) and `unitPrice == nil`. `volumeL`, `fuelKind` and `date` are
    /// non-optional - a typed entry always records them, so they are never
    /// blank and never suggested.
    public static func suggestions(entry: FillUp, extraction: FuelExtraction) -> Set<FieldRef> {
        var result = Set<FieldRef>()
        if entry.money == nil {
            if extraction.total != nil { result.insert(.total) }
            if extraction.currency != nil { result.insert(.currency) }
        }
        if entry.unitPrice == nil, extraction.unitPrice != nil {
            result.insert(.unitPrice)
        }
        return result
    }
}
