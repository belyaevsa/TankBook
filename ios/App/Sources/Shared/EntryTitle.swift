import Foundation
import TankbookCore

/// The one title a log-like row shows for an entry (RV.187). Every surface that
/// renders an entry's title - the Log row, the duplicate card, the
/// excluded-entries list, the flagged list, Recently deleted - resolves it here,
/// so two surfaces can never disagree about what an entry is called.
///
/// A fill shows its station (else its fuel kind); a charge its provider; a
/// service its vendor, else its first named line item (with a count when it has
/// more), else its category, else the bare type name; an expense its title,
/// else its category, else the bare type name. The bare type name is the LAST
/// resort - never the answer while better text exists.
enum EntryTitle {
    static func text(_ entry: any Entry, stations: [Station]) -> String {
        switch entry {
        case let fill as FillUp:
            if let stationID = fill.stationId,
               let name = stations.first(where: { $0.id == stationID })?.name {
                return name
            }
            return fill.fuelKind.fuelKindLabel
        case let charge as ChargeSession:
            return charge.provider ?? L10n.localize("Charge")
        case let service as ServiceRecord:
            return serviceTitle(vendor: service.vendor,
                                itemTitles: service.items.map(\.title),
                                category: service.items.first?.category)
        case let expense as Expense:
            return expenseTitle(expense.title, category: expense.category)
        default:
            return L10n.localize("Entry")
        }
    }

    static func text(_ entry: LogStream.LogEntry, stations: [Station]) -> String {
        switch entry.kind {
        case .fuel:
            if let stationID = entry.stationId,
               let name = stations.first(where: { $0.id == stationID })?.name {
                return name
            }
            return entry.fuelKind?.fuelKindLabel ?? L10n.localize("Fuel")
        case .charge:
            return entry.provider ?? L10n.localize("Charge")
        case .service:
            return serviceTitle(vendor: entry.vendor,
                                itemTitles: entry.serviceItemTitles,
                                category: entry.serviceCategory)
        case .expense:
            return expenseTitle(entry.entryTitle, category: entry.expenseCategory)
        }
    }

    /// The service chain (RV.187): vendor, then the first NAMED line item (the
    /// rest are counted - "first item plus a count"), then the first item's
    /// category, then the bare type name.
    private static func serviceTitle(vendor: String?, itemTitles: [String],
                                     category: ServiceCategory?) -> String {
        if let vendor, !vendor.isEmpty { return vendor }
        let named = itemTitles.filter { !$0.isEmpty }
        if let first = named.first {
            guard named.count > 1 else { return first }
            return L10n.serviceItemsTitle(first: first, extraCount: named.count - 1)
        }
        if let category { return L10n.serviceCategoryLabel(category) }
        return L10n.localize("Service")
    }

    /// The expense chain (RV.187): its title, then its category, then the bare
    /// type name.
    private static func expenseTitle(_ title: String?, category: ExpenseCategory?) -> String {
        if let title, !title.isEmpty { return title }
        if let category { return L10n.expenseCategoryLabel(category) }
        return L10n.localize("Expense")
    }
}
