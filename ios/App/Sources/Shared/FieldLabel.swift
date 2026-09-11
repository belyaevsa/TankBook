import Foundation
import TankbookCore

// MARK: - RV.201 the ONE field-label table
//
// The attach path's recognised page (`AttachmentValueFormat`) and the inbox
// comparison (`InboxValueFormat`) render the same `FieldRef` vocabulary. Before
// this row each owned its own switch, and the inbox's returned `""` for every
// field outside the six fuel ones - so a service vendor or an invoice line the
// attach page already named rendered as a blank cell. Both now call this, so a
// new `FieldRef` case has exactly one label to add and the two surfaces cannot
// drift into two tables (RV.169's complaint, arriving as copy).

/// The display label for a field ref, in the current locale.
enum FieldLabel {
    static func text(_ field: FieldRef) -> String {
        switch field {
        case .date: return L10n.localize("Date")
        case .fuelKind: return L10n.localize("Fuel")
        case .volume: return L10n.localize("Litres")
        case .unitPrice: return L10n.localize("Price/L")
        case .total: return L10n.localize("Total")
        case .currency: return L10n.localize("Currency")
        case .station: return L10n.localize("Station")
        case .vendor: return L10n.localize("Vendor")
        case .energy: return L10n.localize("Energy")
        case .category: return L10n.localize("Category")
        case .lineItem(let n):
            // `FieldRef.lineItem` is an INDEX into the entry's `items` (the merge
            // and the recognition both address it that way); the user counts from
            // one, so only the LABEL is offset. Offsetting the ref itself would
            // make the merge write the wrong line.
            return String(format: L10n.localize("Row %@"), String(n + 1))
        }
    }
}
