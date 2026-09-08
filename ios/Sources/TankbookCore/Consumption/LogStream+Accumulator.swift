import Foundation

// MARK: - The shared month-spend accumulator (RV.112)

extension LogStream.MonthTotal {
    /// The month-spend accumulator and classifier that every surface deriving a
    /// month's spend reduces through - the Log divider (`LogStream.section`),
    /// `HomeStats.monthSpend` and `TrendsStats`' monthly series all feed it, so
    /// the three are structurally incapable of disagreeing about a month's
    /// figure or its honesty (RV.112). What differs between the callers is the
    /// ITERATION, never the money rule: LogStream walks rendered rows (a
    /// purchase group counted once by its grand total - hard rule 4; an S2
    /// duplicate card only its counted member - docs/SYNC.md S2), the stats walk
    /// their already-counted entry lists; every money pair reaches the same
    /// `add(_:)` here. Kept in its own file so `LogStream.swift` stays under the
    /// lint ceiling.
    ///
    /// The accumulator also owns the CURRENCY axis (RV.145): a known home amount
    /// is banked under its own `homeCurrency`, so a month whose known figures
    /// span currencies classifies `.mixed` - never a bare total that is not a
    /// quantity of anything - and every amount the classifier emits is paired
    /// with the currency it is denominated in. `vehicleHome` names the currency
    /// of a money-less month's honest zero (a month of only free events has no
    /// row to say what currency its `0 €` is in, so the vehicle's home stamps
    /// it, as the divider always did).
    public struct Accumulator: Equatable, Sendable {
        /// Each KNOWN home amount banked under its own currency - the classifier
        /// reads this, never a single currency-blind running total (the sum that
        /// could not tell a euro from a dollar, RV.145).
        private var amountsByCurrency: [CurrencyCode: Decimal] = [:]
        /// The count of money-bearing rows still waiting on a rate.
        public private(set) var pendingCount = 0
        /// The currency a money-less month's zero is denominated in.
        private let vehicleHome: CurrencyCode

        public init(vehicleHome: CurrencyCode) {
            self.vehicleHome = vehicleHome
        }

        /// One money pair's contribution to the month total (docs/SCHEMA.md ->
        /// Money). A known home amount sums in under its own home currency; a
        /// rate-pending pair is COUNTED but never summed as zero - its home
        /// amount is not known, and a derived figure that asserts a falsehood
        /// is the defect (RV.106, RV.112). `money == nil` (a free event) is
        /// neither: it has no spend and is not waiting on anything.
        public mutating func add(_ money: Money?) {
            if money?.isRatePending == true {
                pendingCount += 1
            } else if let money, let amount = money.homeAmount {
                amountsByCurrency[money.homeCurrency, default: .zero] += amount
            }
        }

        /// Adds every money pair in `moneys` in order.
        public mutating func add<C: Sequence>(contentsOf moneys: C) where C.Element == Money? {
            for money in moneys {
                add(money)
            }
        }

        /// The month's stated figure, classified exactly as the divider's:
        /// `.complete` when nothing is pending, `.partial` when a known sum
        /// exists beside pending rows, `.pending` when no home figure exists
        /// at all - a zero sum with pending rows is never printed as fact - and
        /// `.mixed` when the KNOWN figures span home currencies, because no
        /// single number then states the month (RV.145). The `.complete`/
        /// `.partial` amounts are denominated in the `currency` they carry.
        public var monthTotal: LogStream.MonthTotal {
            let subtotals = Self.orderedSubtotals(amountsByCurrency)
            if subtotals.isEmpty {
                if pendingCount == 0 {
                    return .complete(amount: .zero, currency: vehicleHome)
                }
                return .pending(pendingCount: pendingCount)
            }
            if subtotals.count == 1, let only = subtotals.first {
                if pendingCount == 0 {
                    return .complete(amount: only.amount, currency: only.currency)
                }
                return .partial(amount: only.amount, currency: only.currency,
                                pendingCount: pendingCount)
            }
            return .mixed(subtotals: subtotals, pendingCount: pendingCount)
        }

        /// The known figures as per-currency subtotals in a stable display
        /// order: largest first (the dominant currency leads a divider), ties
        /// broken by code so the order never depends on iteration.
        private static func orderedSubtotals(_ amounts: [CurrencyCode: Decimal]) -> [LogStream.SpendSubtotal] {
            amounts.map { LogStream.SpendSubtotal(amount: $0.value, currency: $0.key) }
                .sorted { lhs, rhs in
                    if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                    return lhs.currency.rawValue < rhs.currency.rawValue
                }
        }
    }
}
