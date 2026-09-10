import Foundation
import TankbookCore

// RV.187 title helpers, kept out of `L10n.swift` so that file stays under the
// lint ceiling. The copy still lives in the String Catalog like every other
// user-facing string.

extension L10n {
    /// The display label for a Service line-item category (RV.187): the title
    /// fallback when a service names no item. `.other`'s free text is runtime
    /// data and renders as itself; an empty `.other` falls back to "Other".
    static func serviceCategoryLabel(_ category: ServiceCategory) -> String {
        switch category {
        case .oil: return localize("Oil")
        case .brakes: return localize("Brakes")
        case .tires: return localize("Tires")
        case .battery: return localize("Battery")
        case .filters: return localize("Filters")
        case .inspection: return localize("Inspection")
        case .repair: return localize("Repair")
        case .parts: return localize("Parts")
        case .wash: return localize("Wash")
        case .other(let value):
            return value.isEmpty ? localize("Other") : value
        }
    }

    /// "Oil change and 2 more" - a multi-item service's title (RV.187): the
    /// first named item plus a count of the rest. One full localised phrase per
    /// language with plural variations on the count, never a spliced stem.
    static func serviceItemsTitle(first: String, extraCount: Int) -> String {
        String(localized: "\(first) and \(extraCount) more")
    }
}
