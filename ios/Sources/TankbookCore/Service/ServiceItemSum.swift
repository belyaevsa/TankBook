import Foundation

/// The exact sum of a service's line-item costs, classified by currency
/// (docs/SCHEMA.md -> ServiceRecord & ServiceItem).
///
/// This is THE one summation of service line costs in the app: the create
/// screen's derived header and the edit screen's money card both call
/// `[ServiceItem].costSum()` (the edit screen through
/// `[ServiceEntryItemDraft].lineSum(homeCurrency:)`), so the two doors cannot
/// state different totals for the same items. A second summation is the defect
/// [RV.169] exists to name.
///
/// The items sum their ORIGINAL amounts, never a home-side conversion: an item
/// cost carries its own `Money` pair, and the conversion is a separate,
/// possibly still-pending figure (hard rule 3 - snapshots are immutable and
/// summing what is there never re-resolves them). Amounts are `Decimal`, never
/// `Double` (docs/SCHEMA.md -> Money).
///
/// Two currencies have no common quantity, so a set whose costs span currencies
/// has no single total. It is `.mixed`, and a renderer shows the per-currency
/// breakdown - never a summed cross-currency figure (hard rule 3, the RV.145
/// rule).
public enum ServiceItemSum: Equatable, Sendable {
    /// No item carries a cost. Nothing is stated; a renderer shows no sum row.
    case none
    /// Every costed item is in `currency`; `amount` is their exact sum. A
    /// renderer prints it with `currency`'s own marker.
    case summed(amount: Decimal, currency: CurrencyCode)
    /// The costs span more than one currency, so no single number states them.
    /// `subtotals` is the per-currency breakdown, largest first, each exact.
    case mixed(subtotals: [Subtotal])

    /// One currency's exact share of a mixed set. Carries its currency so the
    /// amount and the marker a renderer prints can never be read from two
    /// different objects (the RV.145 defect).
    public struct Subtotal: Equatable, Sendable {
        public let amount: Decimal
        public let currency: CurrencyCode

        public init(amount: Decimal, currency: CurrencyCode) {
            self.amount = amount
            self.currency = currency
        }
    }

    /// The single summed amount, or nil when there is none to state: `.none`
    /// states nothing and `.mixed` has no single figure (hard rule 3).
    public var summedAmount: Decimal? {
        if case .summed(let amount, _) = self { return amount }
        return nil
    }

    /// The single currency of a `.summed` set, or nil otherwise.
    public var summedCurrency: CurrencyCode? {
        if case .summed(_, let currency) = self { return currency }
        return nil
    }
}

public extension Array where Element == ServiceItem {
    /// Sums the items' original cost amounts, grouped by currency. An item
    /// without a cost contributes nothing, so a blank-cost row never breaks the
    /// sum. The subtotals are ordered largest first, ties broken by code, so the
    /// breakdown never depends on iteration.
    func costSum() -> ServiceItemSum {
        var amountsByCurrency: [CurrencyCode: Decimal] = [:]
        for item in self {
            guard let cost = item.cost else { continue }
            amountsByCurrency[cost.currency, default: .zero] += cost.amount
        }
        let subtotals = amountsByCurrency
            .map { ServiceItemSum.Subtotal(amount: $0.value, currency: $0.key) }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.currency.rawValue < rhs.currency.rawValue
            }
        guard let only = subtotals.first else { return .none }
        guard subtotals.count == 1 else { return .mixed(subtotals: subtotals) }
        return .summed(amount: only.amount, currency: only.currency)
    }
}
