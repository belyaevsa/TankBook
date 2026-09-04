import Foundation

// MARK: - RV.62 the expense prefill
//
// What one Expense-mode capture may hand the expense form. A shop receipt is
// not a fuel receipt: liters, unit price and fuel kind are meaningless on it,
// while total, currency and date are the fields that matter - and
// `ExtractionAssembler` already resolves all three. This type is the
// deliberately narrow channel that carries exactly those three across the
// app's in-memory hand-off (`ExpenseEntrySession`), and the builder is the one
// place a `FuelExtraction` becomes an expense pre-fill.
//
// The type is the guard, not just the builder: it has NO liters / unitPrice /
// fuelKind members, so piping the fill-up prefill across is not a mistake that
// slips through review - it is something the shape of this value refuses to
// express. Every carried value is default input the user edits (hard rule 13),
// never a fact; an all-nil extraction becomes an empty prefill, which the form
// renders as the ordinary empty sheet, never an error (hard rule 7).

/// The pre-fill one Expense-mode scan offers the expense form. Lives in core
/// (never the app target) so the extraction -> prefill mapping is L1-testable
/// with no image and no view, the same tier rule `ExtractionAssembler` obeys.
public struct ExpensePrefill: Sendable, Equatable {
    /// The receipt's own total, exact `Decimal` (money, `docs/SCHEMA.md`).
    public var total: Decimal?
    /// The receipt's currency, when the marker lookup resolved one. The app
    /// uses it as the honesty gate for `total` - see ExpenseEntryView - because
    /// the expense form has no foreign-currency affordance: a total priced in
    /// a currency the form cannot express must not be offered as if it were the
    /// vehicle's home currency.
    public var currency: CurrencyCode?
    /// The receipt's printed date, parsed to a `Date`. `nil` means no date was
    /// read - the form keeps its own default, never a wrong fact.
    public var date: Date?

    public init(total: Decimal? = nil, currency: CurrencyCode? = nil, date: Date? = nil) {
        self.total = total
        self.currency = currency
        self.date = date
    }
}

/// The one seam where a `FuelExtraction` becomes an `ExpensePrefill`. It maps
/// exactly three fields - total, currency, date - and deliberately none of the
/// fuel fields. This is the L1-pinned boundary that stops someone piping the
/// fill-up prefill across later: an extraction may carry liters and fuel kind,
/// and this function is where they are left behind.
public enum ExpensePrefillBuilder {
    public static func prefill(from extraction: FuelExtraction) -> ExpensePrefill {
        ExpensePrefill(
            total: extraction.total,
            currency: extraction.currency,
            date: extraction.date.flatMap { ConfirmDate.parse($0) })
    }
}
