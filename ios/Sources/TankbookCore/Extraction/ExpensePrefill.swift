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
    /// The receipt's currency, when the marker lookup resolved one. The expense
    /// form carries a currency chip row, so this rides WITH `total`: a foreign
    /// total is pre-filled in its own currency, the chip row lets the user
    /// change it, and the save snapshots the pair at the entry's own date
    /// (RV.279). Nil means the scan read no currency - the form keeps the car's
    /// home currency as its default.
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

    /// The ONE seam where a cloud `GatewayExtraction` becomes the expense form's
    /// pre-fill AND the inbox's recognition (PJ.29). Both are built here, from
    /// one decode, so the on-time route (fill the open form) and the late route
    /// (offer the saved entry) cannot drift: the amount, currency, date and
    /// category the form would take are exactly the ones the inbox offers.
    ///
    /// The field set is the expense kind's own - total, currency, date,
    /// category - and never the fuel fields a `receipt` answer might also carry.
    /// A nil field is absent, never guessed (hard rule 13); an unknown category
    /// string was already dropped by the wire decode.
    public static func reading(fromGateway extraction: GatewayExtraction) -> ExpenseGatewayReading {
        let prefill = ExpensePrefill(
            total: extraction.total?.value,
            currency: extraction.currency?.value,
            date: extraction.date.flatMap { ConfirmDate.parse($0.value) })
        let recognition = ExpenseRecognition(
            total: extraction.total,
            currency: extraction.currency,
            category: extraction.category,
            date: prefill.date.map { GatewayFieldValue(value: $0, confidence: 0.9) })
        return ExpenseGatewayReading(prefill: prefill, recognition: recognition)
    }

    /// The pre-fill half alone. A caller with no use for the recognition (the
    /// screenshot/test path) takes this; the form takes `reading(fromGateway:)`
    /// so both halves stay one decode.
    public static func prefill(fromGateway extraction: GatewayExtraction) -> ExpensePrefill {
        reading(fromGateway: extraction).prefill
    }
}

/// What one cloud `expense` reading offers, on time and late: the pre-fill the
/// open form takes and the recognition the inbox compares against a saved
/// entry. Produced together so the two routes cannot disagree about what the
/// receipt said.
public struct ExpenseGatewayReading: Sendable, Equatable {
    public var prefill: ExpensePrefill
    public var recognition: ExpenseRecognition

    public init(prefill: ExpensePrefill, recognition: ExpenseRecognition) {
        self.prefill = prefill
        self.recognition = recognition
    }
}

extension ExpenseCategory {
    /// The category a gateway `expense` answer's `category` string names, or nil
    /// for a string the device does not know - the value is dropped, never
    /// guessed (hard rule 13). `wash` is the `.other` escape hatch the shipped
    /// vocabulary uses (docs/EXTRACTION.md, RV.200), and `other` is the bare
    /// `.other("")`.
    public init?(gatewayValue: String) {
        switch gatewayValue {
        case "insurance": self = .insurance
        case "tax": self = .tax
        case "parking": self = .parking
        case "toll": self = .toll
        case "fine": self = .fine
        case "accessory": self = .accessory
        case "parts": self = .parts
        case "wash": self = .other("wash")
        case "other": self = .other("")
        default: return nil
        }
    }
}
