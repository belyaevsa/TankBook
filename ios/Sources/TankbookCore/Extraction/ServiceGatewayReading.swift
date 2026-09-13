import Foundation

// MARK: - PJ.29a the cloud invoice reading
//
// A service invoice is a document kind of its own at the gateway (`kind:
// "invoice"`): the provider is asked for the header only - vendor, total, date,
// currency - because the line items are the device's deterministic split
// (docs/JOURNEYS.md J7, `InvoiceSplitter`). This file is the ONE core seam that
// turns a `GatewayExtraction` into the header pre-fill the form takes and the
// `ServiceRecognition` the inbox compares against a saved record, so the
// on-time and late routes cannot disagree about what the invoice's header said.
//
// The type is the guard, not just the builder: `ServicePrefill` has no line-item
// member, so a cloud answer can never carry line items across - the local
// split's items are the form's and stay untouched (hard rule 13). An all-nil
// extraction becomes an empty prefill, which the form renders as the ordinary
// empty sheet, never an error (hard rule 7).

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
/// header pre-fill AND the inbox's recognition (PJ.29a). Both are built here,
/// from one decode. The field set is the invoice header's own - vendor, total,
/// currency, date - and `lineItems` is deliberately EMPTY: the line items are
/// the local deterministic split's, and a cloud answer never replaces them
/// (docs/JOURNEYS.md J7). A nil field is absent, never guessed (hard rule 13);
/// an unknown currency string was already dropped by the wire decode.
public enum ServiceRecognitionBuilder {
    public static func reading(fromGateway extraction: GatewayExtraction) -> ServiceGatewayReading {
        let date = extraction.date.flatMap { ConfirmDate.parse($0.value) }
        let prefill = ServicePrefill(
            vendor: extraction.vendor?.value,
            total: extraction.total?.value,
            currency: extraction.currency?.value,
            date: date)
        let recognition = ServiceRecognition(
            vendor: extraction.vendor,
            total: extraction.total,
            currency: extraction.currency,
            date: date.map { GatewayFieldValue(value: $0, confidence: 0.9) },
            lineItems: [])
        return ServiceGatewayReading(prefill: prefill, recognition: recognition)
    }
}
