import Foundation

// MARK: - The cloud invoice reading
//
// A service invoice is a document kind of its own at the gateway (`kind:
// "invoice"`). Sent the header-only way the provider reads vendor, total, date
// and currency; sent as pages (docs/API.md "multi-page invoices") it reads the
// line items too, and this file is the ONE core seam that turns a
// `GatewayExtraction` into the header pre-fill the form takes and the
// `ServiceRecognition` the inbox and the open form compare against the local
// split, so the on-time and late routes cannot disagree about what the
// invoice said.
//
// The line items are OFFERS, never a replacement: the local deterministic
// split (`InvoiceSplitter`) stays the form's, and `LineMatcher` pairs each
// cloud line onto it with keep-mine as the default (hard rule 13). The
// arithmetic gate marks a reading whose lines do not sum to its total. An
// all-nil extraction becomes an empty prefill, which the form renders as the
// ordinary empty sheet, never an error (hard rule 7).

/// The header one cloud `invoice` reading offers the service form. Lives in core
/// (never the app target) so the extraction -> prefill mapping is L1-testable
/// with no view, the same tier rule `ExpensePrefill` obeys.
public struct ServicePrefill: Sendable, Equatable {
    /// The workshop the invoice names. Nil means the cloud read no vendor - the
    /// form keeps whatever the local split left, never a guessed name.
    public var vendor: String?
    /// The invoice's own total, exact `Decimal` (money, `docs/SCHEMA.md`). The
    /// service form derives its header total from the line items, so this is
    /// offered through `ServiceRecognition` rather than typed into a field; it
    /// rides here so the prefill and the recognition are one decode.
    public var total: Decimal?
    /// The currency the invoice is priced in, when the marker lookup resolved
    /// one. Nil means the cloud read no currency - the form keeps the car's home
    /// currency as its default.
    public var currency: CurrencyCode?
    /// The invoice's printed date, parsed to a `Date`. Nil means no date was
    /// read - the form keeps its own default, never a wrong fact.
    public var date: Date?

    public init(vendor: String? = nil, total: Decimal? = nil,
                currency: CurrencyCode? = nil, date: Date? = nil) {
        self.vendor = vendor
        self.total = total
        self.currency = currency
        self.date = date
    }
}

/// What one cloud `invoice` reading offers, on time and late: the header
/// pre-fill the open form takes and the recognition the inbox compares against a
/// saved record. Produced together so the two routes cannot disagree about what
/// the invoice's header said.
public struct ServiceGatewayReading: Sendable, Equatable {
    public var prefill: ServicePrefill
    public var recognition: ServiceRecognition

    public init(prefill: ServicePrefill, recognition: ServiceRecognition) {
        self.prefill = prefill
        self.recognition = recognition
    }
}

/// The ONE seam where a cloud `GatewayExtraction` becomes the service form's
/// header pre-fill AND the recognition the form and the inbox pair onto the
/// local split. Both are built here, from one decode. A nil field is absent,
/// never guessed (hard rule 13); an unknown currency string was already
/// dropped by the wire decode.
///
/// A line item needs a title to be offered (a bare amount names nothing);
/// its cost is the line's amount in the reading's currency, else in
/// `homeCurrency` when the caller knows one, else no cost. A line whose
/// category the device did not recognise is offered as `.other("")` - the
/// device's own code for "a line, unclassified".
public enum ServiceRecognitionBuilder {
    public static func reading(fromGateway extraction: GatewayExtraction,
                               homeCurrency: CurrencyCode? = nil) -> ServiceGatewayReading {
        let date = extraction.date.flatMap { ConfirmDate.parse($0.value) }
        let prefill = ServicePrefill(
            vendor: extraction.vendor?.value,
            total: extraction.total?.value,
            currency: extraction.currency?.value,
            date: date)
        let currency = extraction.currency?.value ?? homeCurrency
        let lines = extraction.lineItems.compactMap { line -> ServiceRecognition.LineItem? in
            guard let title = line.title?.value else { return nil }
            let cost = line.amount.flatMap { amount -> Money? in
                guard let currency else { return nil }
                return Money(amount: amount.value, currency: currency, homeCurrency: homeCurrency ?? currency)
            }
            return ServiceRecognition.LineItem(title: title, category: line.category?.value ?? .other(""), cost: cost)
        }
        let recognition = ServiceRecognition(
            vendor: extraction.vendor,
            total: extraction.total,
            currency: extraction.currency,
            date: date.map { GatewayFieldValue(value: $0, confidence: 0.9) },
            lineItems: lines,
            doesNotAddUp: Self.doesNotAddUp(lines: extraction.lineItems, total: extraction.total?.value))
        return ServiceGatewayReading(prefill: prefill, recognition: recognition)
    }

    /// The arithmetic gate: the lines' amounts against the header total within
    /// CHECK 3's tolerance (`ConfirmConfidenceGate.crossCheckTolerance`). A
    /// reading with no lines or no total is not checked - nothing to sum.
    static func doesNotAddUp(lines: [GatewayLineItem], total: Decimal?) -> Bool {
        let amounts = lines.compactMap { $0.amount?.value }
        guard let total, !amounts.isEmpty else { return false }
        let sum = amounts.reduce(Decimal(0), +)
        return abs(sum - total) > ConfirmConfidenceGate.crossCheckTolerance(amount: total)
    }
}

extension ServiceCategory {
    /// The line-item category vocabulary the gateway forwards (docs/API.md
    /// "multi-page invoices"): the model's word mapped onto the device's own
    /// codes, exactly as `ExpenseCategory(gatewayValue:)` does. An unknown
    /// string is nil - the line keeps no category rather than a guessed one
    /// (hard rule 13).
    public init?(gatewayValue: String) {
        guard let category = Self.gatewayVocabulary[gatewayValue.lowercased()] else { return nil }
        self = category
    }

    private static let gatewayVocabulary: [String: ServiceCategory] = [
        "oil": .oil, "brakes": .brakes, "tires": .tires, "tyres": .tires, "battery": .battery,
        "filters": .filters, "filter": .filters, "inspection": .inspection,
        "repair": .repair, "labour": .repair, "labor": .repair, "parts": .parts, "wash": .wash,
        "fee": .other(""), "other": .other("")
    ]
}
