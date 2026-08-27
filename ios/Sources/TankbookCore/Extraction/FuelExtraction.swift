import Foundation

/// Extraction result for one receipt / pump photo. All fields are optional
/// because the parser is a suggestion engine (CLAUDE.md hard rule 13): an
/// uncertain field is returned nil so the user fills it, never a confident
/// wrong value.
public struct FuelExtraction: Sendable, Equatable, Codable {
    public var liters: Double?
    public var unitPrice: Double?
    public var total: Double?
    public var currency: CurrencyCode?
    public var fuelKind: FuelKind?
    public var date: String?
    /// The four-outcome cross-check of `liters x unitPrice` vs `total`
    /// (docs/EXTRACTION.md -> "Cross-check: four outcomes, not two"). Computed
    /// by `FuelExtractor.extract`; a manually-built extraction carries the
    /// default `.notApplicable` - run `ExtractionCrossCheck.evaluate` when the
    /// document lines are available.
    public var crossCheck: ExtractionCrossCheck = .notApplicable

    /// A P2.13 seven-segment digit repair, when one fired. The presence of a
    /// repair is the marker that the affected field is a **suggestion** the
    /// user must confirm (hard rule 13): `FuelExtractor` keeps `crossCheck` a
    /// `mismatch` so the confirm screen never locks a repaired triple. nil when
    /// no single-digit substitution uniquely closed the arithmetic.
    public var digitRepair: DigitRepair.Result?

    public init(
        liters: Double? = nil,
        unitPrice: Double? = nil,
        total: Double? = nil,
        currency: CurrencyCode? = nil,
        fuelKind: FuelKind? = nil,
        date: String? = nil,
        crossCheck: ExtractionCrossCheck = .notApplicable,
        digitRepair: DigitRepair.Result? = nil
    ) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.currency = currency
        self.fuelKind = fuelKind
        self.date = date
        self.crossCheck = crossCheck
        self.digitRepair = digitRepair
    }

    /// The fuel-line amount when volume and price are both known, else nil.
    /// On a mixed receipt this is the amount the fill-up records (hard rule 4),
    /// distinct from the receipt's grand total.
    public var fuelLineAmount: Double? {
        guard let liters, let unitPrice else { return nil }
        return liters * unitPrice
    }
}

/// The input class the extractor is pointed at. Fuel kind is read only from
/// receipt/screenshot/fiscal product lines, never from a pump display, where
/// the grade labels belong to every nozzle rather than this fill.
public enum ExtractionSource: String, Sendable, Equatable {
    case receipt
    case pump
    case fiscal
    case screenshot
}
