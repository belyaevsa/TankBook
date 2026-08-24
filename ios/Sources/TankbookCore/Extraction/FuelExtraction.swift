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

    public init(
        liters: Double? = nil,
        unitPrice: Double? = nil,
        total: Double? = nil,
        currency: CurrencyCode? = nil,
        fuelKind: FuelKind? = nil,
        date: String? = nil
    ) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.currency = currency
        self.fuelKind = fuelKind
        self.date = date
    }

    /// liters × unitPrice ≈ total under the CHECK 3 tolerance
    /// (docs/SCHEMA.md: max(0.02, amount × 0.005)). A green check validates the
    /// product, never the assignment - the multiplication is commutative.
    public var crossCheckPassed: Bool {
        guard let liters, let unitPrice, let total else { return false }
        return abs(liters * unitPrice - total) <= max(0.02, total * 0.005)
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
