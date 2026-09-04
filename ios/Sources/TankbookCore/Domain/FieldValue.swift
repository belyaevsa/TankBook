import Foundation

// MARK: - RV.48 the typed value a field extraction read

/// The typed value a field extraction read (docs/SCHEMA.md, FieldExtraction.value).
///
/// Money fields (`.total`, `.unitPrice`) are `Decimal` never `Double` (P2.2b);
/// the currency for a money value is the sibling `.currency` field, so the pair
/// is the two fields together (docs/SCHEMA.md, "Money is always a pair").
/// Volume and energy are `Double` (measurements, like `FillUp.volumeL` and
/// `ChargeSession.energyKWh`). Date, station and vendor are the raw `String` as
/// read, byte-identical to what was printed (P2.11). Fuel kind and currency are
/// their enums.
public enum FieldValue: Codable, Sendable, Equatable, Hashable {
    /// `.total`, `.unitPrice` - the amount; the currency is the sibling
    /// `.currency` field.
    case money(Decimal)
    /// `.volume` (litres), `.energy` (kWh) - a measured quantity.
    case number(Double)
    /// `.date` (the raw date string), `.station`, `.vendor` - free text.
    case text(String)
    case fuelKind(FuelKind)
    case currency(CurrencyCode)
}

// MARK: - Payload encoding (tagged object, mirrors the gateway's `{ value, confidence }`)

extension FieldValue {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .money(let amount):
            try c.encode("money", forKey: key("tag"))
            try c.encode(PayloadFormat.decimalString(amount), forKey: key("value"))
        case .number(let number):
            try c.encode("number", forKey: key("tag"))
            try c.encode(number, forKey: key("value"))
        case .text(let text):
            try c.encode("text", forKey: key("tag"))
            try c.encode(text, forKey: key("value"))
        case .fuelKind(let kind):
            try c.encode("fuelKind", forKey: key("tag"))
            try c.encode(kind, forKey: key("value"))
        case .currency(let code):
            try c.encode("currency", forKey: key("tag"))
            try c.encode(code, forKey: key("value"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "money":
            guard let raw = try c.decodeIfPresent(String.self, forKey: key("value")),
                  let amount = PayloadFormat.decimal(from: raw) else {
                throw dataCorrupted("FieldValue.money is not a decimal string")
            }
            self = .money(amount)
        case "number":
            self = .number(try c.decode(Double.self, forKey: key("value")))
        case "text":
            self = .text(try c.decode(String.self, forKey: key("value")))
        case "fuelKind":
            guard let kind = FuelKind(rawValue: try c.decode(String.self, forKey: key("value"))) else {
                throw dataCorrupted("Unknown fuelKind FieldValue")
            }
            self = .fuelKind(kind)
        case "currency":
            guard let code = CurrencyCode(rawValue: try c.decode(String.self, forKey: key("value"))) else {
                throw dataCorrupted("Unknown currency FieldValue")
            }
            self = .currency(code)
        default:
            throw dataCorrupted("Unknown FieldValue tag")
        }
    }
}

// MARK: - The value-bearing subset of an ExtractionMeta (RV.48)

extension ExtractionMeta {
    /// Whether any field carries an assigned value. The gate for storing an
    /// assignment on the `Attachment`: a parse that assigned nothing stores no
    /// container at all, never an empty one (RV.48). Only `value` counts -
    /// `cropRect` and `userCorrected` are provenance, not something the user
    /// reads off the receipt.
    public var hasAssignedValue: Bool {
        fields.values.contains { $0.value != nil }
    }

    /// The value-bearing subset of `fields` - a field the parse resolved but did
    /// not assign a value to is absent from the result. The `Attachment`'s
    /// stored assignment is this subset, never the full provenance map.
    public var assignedFields: [FieldRef: FieldExtraction] {
        fields.filter { $0.value.value != nil }
    }

    /// A copy whose `fields` carries only the assigned values; nil when nothing
    /// was assigned. This is the exact shape the `Attachment` persists.
    public var assignmentOnly: ExtractionMeta? {
        let assigned = assignedFields
        guard !assigned.isEmpty else { return nil }
        return ExtractionMeta(fields: assigned, pipeline: pipeline)
    }
}
