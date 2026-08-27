import Foundation

/// Extraction result for one receipt / pump photo. All fields are optional
/// because the parser is a suggestion engine (CLAUDE.md hard rule 13): an
/// uncertain field is returned nil so the user fills it, never a confident
/// wrong value.
public struct FuelExtraction: Sendable, Equatable, Codable {
    /// Volume, always in litres. Deliberately `Double` - `docs/SCHEMA.md` types
    /// `volumeL: Double` on purpose: it is a volume, not money. Only `unitPrice`
    /// and `total` are money and therefore `Decimal` (P2.2b).
    public var liters: Double?
    /// Money. `Decimal` because `docs/SCHEMA.md` types money as `Decimal`, and a
    /// `Double` does not survive a binary-float round trip (`4201.68` is not
    /// exactly representable). Born exact at the OCR boundary through
    /// `ConfirmFormat.decimal(fromExtraction:)` - never `Decimal(Double)`.
    public var unitPrice: Decimal?
    /// Money. Same rationale as `unitPrice`.
    public var total: Decimal?
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
        unitPrice: Decimal? = nil,
        total: Decimal? = nil,
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
    /// distinct from the receipt's grand total. Money, so `Decimal`: the volume
    /// enters through the exact `ConfirmFormat` boundary (never `Decimal(Double)`)
    /// and multiplies the already-exact `unitPrice`.
    public var fuelLineAmount: Decimal? {
        guard let liters, let unitPrice else { return nil }
        let volume = ConfirmFormat.decimal(
            fromExtraction: liters, fractionDigits: ConfirmFormat.fractionDigits(for: .volume)) ?? 0
        return volume * unitPrice
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
