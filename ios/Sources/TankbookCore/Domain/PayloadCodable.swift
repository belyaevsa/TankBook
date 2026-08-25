import Foundation
import CoreGraphics

// MARK: - Payload encoding conventions
//
// The payload contract (docs/SYNC.md -> "Payload contract and versioning",
// docs/SCHEMA.md -> "Payload schemas") needs a JSON shape the synthesized
// Codable does not produce:
//
//   - Money:   decimals as JSON strings, dates as ISO-8601 strings.
//   - enums with payloads: a tagged object `{ "tag": <case>, ... }`, using the
//     exact SCHEMA.md spellings - Swift's synthesized `{"case": {...}}` shape
//     is unstable (`{"other":{"_0":"tuning"}}`) and hard to version.
//   - FieldRef: a plain string ("volume", "lineItem(3)") so `[FieldRef: ...]`
//     dictionaries become real JSON objects (the synthesized form is an array
//     of key/value pairs).
//   - FieldExtraction.cropRect: a flat `{x, y, width, height}` object
//     (synthesized CGRect is `[[x,y],[w,h]]`).
//
// These conformances override the synthesized ones; the schema generator
// (`scripts/generate-payload-schemas.swift`) and the fixture corpus describe
// exactly this shape.

/// A throwaway CodingKey for payload keyed containers. The field set is a
/// closed, developer-maintained list, so a single key type avoids one
/// `CodingKeys` enum per struct.
internal struct PayloadCodingKey: CodingKey, Hashable, Sendable {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    init(_ string: String) { self.stringValue = string; self.intValue = nil }
}

private func key(_ string: String) -> PayloadCodingKey { PayloadCodingKey(string) }

private func dataCorrupted(_ error: String) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: error))
}

// MARK: - Money

extension Money {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        try c.encode(PayloadFormat.decimalString(amount), forKey: key("amount"))
        try c.encode(currency.rawValue, forKey: key("currency"))
        try c.encodeIfPresent(homeAmount.map(PayloadFormat.decimalString), forKey: key("homeAmount"))
        try c.encode(homeCurrency.rawValue, forKey: key("homeCurrency"))
        try c.encodeIfPresent(rate.map(PayloadFormat.decimalString), forKey: key("rate"))
        try c.encodeIfPresent(rateDate.map(PayloadFormat.dateString), forKey: key("rateDate"))
        try c.encode(rateSource.rawValue, forKey: key("rateSource"))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        guard let amount = try c.decode(String.self, forKey: key("amount")).withPayloadDecimal else {
            throw dataCorrupted("Money.amount is not a decimal string")
        }
        guard let currency = CurrencyCode(rawValue: try c.decode(String.self, forKey: key("currency"))) else {
            throw dataCorrupted("Money.currency is not a valid currency code")
        }
        guard let homeCurrency = CurrencyCode(rawValue: try c.decode(String.self, forKey: key("homeCurrency"))) else {
            throw dataCorrupted("Money.homeCurrency is not a valid currency code")
        }
        let homeAmount = try c.decodeIfPresent(String.self, forKey: key("homeAmount")).flatMap(\.withPayloadDecimal)
        let rate = try c.decodeIfPresent(String.self, forKey: key("rate")).flatMap(\.withPayloadDecimal)
        let rateDate = try c.decodeIfPresent(String.self, forKey: key("rateDate")).flatMap(PayloadFormat.date)
        let sourceRaw = try c.decode(String.self, forKey: key("rateSource"))
        let source = RateSource(rawValue: sourceRaw) ?? .ecb
        self.init(amount: amount, currency: currency,
                  homeAmount: homeAmount, homeCurrency: homeCurrency,
                  rate: rate, rateDate: rateDate, rateSource: source)
    }
}

private extension String {
    var withPayloadDecimal: Decimal? { PayloadFormat.decimal(from: self) }
}

// MARK: - Tagged-object enums
//
// Shape: `{ "tag": <case-name>, <payload keys> }`. Unknown tags are rejected
// here; the codec pre-sanitizes unknown tags before decoding and splices the
// original bytes back on encode (forward compatibility, docs/SYNC.md).

extension Provenance {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .receiptScan: try c.encode("receiptScan", forKey: key("tag"))
        case .pumpPhoto: try c.encode("pumpPhoto", forKey: key("tag"))
        case .fiscalQR: try c.encode("fiscalQR", forKey: key("tag"))
        case .screenshot: try c.encode("screenshot", forKey: key("tag"))
        case .manual: try c.encode("manual", forKey: key("tag"))
        case .import(let source):
            try c.encode("import", forKey: key("tag"))
            try c.encode(source, forKey: key("source"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "receiptScan": self = .receiptScan
        case "pumpPhoto": self = .pumpPhoto
        case "fiscalQR": self = .fiscalQR
        case "screenshot": self = .screenshot
        case "manual": self = .manual
        case "import": self = .import(source: try c.decode(String.self, forKey: key("source")))
        default: throw dataCorrupted("Unknown provenance tag")
        }
    }
}

extension ConflictState {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .none:
            try c.encode("none", forKey: key("tag"))
        case .flagged(let kind, let detectedAt):
            try c.encode("flagged", forKey: key("tag"))
            try c.encode(kind.rawValue, forKey: key("kind"))
            try c.encode(PayloadFormat.dateString(detectedAt), forKey: key("detectedAt"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "none":
            self = .none
        case "flagged":
            let kindRaw = try c.decodeIfPresent(String.self, forKey: key("kind")) ?? "order"
            guard let kind = ConflictKind(rawValue: kindRaw),
                  let detectedAtRaw = try c.decodeIfPresent(String.self, forKey: key("detectedAt")),
                  let detectedAt = PayloadFormat.date(from: detectedAtRaw) else {
                throw dataCorrupted("Malformed flagged conflict state")
            }
            self = .flagged(kind: kind, detectedAt: detectedAt)
        default:
            throw dataCorrupted("Unknown conflict tag")
        }
    }
}

extension CrossCheckState {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .verified:
            try c.encode("verified", forKey: key("tag"))
        case .notApplicable:
            try c.encode("notApplicable", forKey: key("tag"))
        case .mismatch(let field):
            try c.encode("mismatch", forKey: key("tag"))
            try c.encode(field.stringValue, forKey: key("field"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "verified": self = .verified
        case "notApplicable": self = .notApplicable
        case "mismatch":
            let fieldRaw = try c.decode(String.self, forKey: key("field"))
            guard let field = FieldRef(string: fieldRaw) else {
                throw dataCorrupted("Unknown mismatch field '\(fieldRaw)'")
            }
            self = .mismatch(field: field)
        default: throw dataCorrupted("Unknown crossCheck tag")
        }
    }
}

extension ServiceCategory {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .oil: try c.encode("oil", forKey: key("tag"))
        case .brakes: try c.encode("brakes", forKey: key("tag"))
        case .tires: try c.encode("tires", forKey: key("tag"))
        case .battery: try c.encode("battery", forKey: key("tag"))
        case .filters: try c.encode("filters", forKey: key("tag"))
        case .inspection: try c.encode("inspection", forKey: key("tag"))
        case .repair: try c.encode("repair", forKey: key("tag"))
        case .parts: try c.encode("parts", forKey: key("tag"))
        case .wash: try c.encode("wash", forKey: key("tag"))
        case .other(let value):
            try c.encode("other", forKey: key("tag"))
            try c.encode(value, forKey: key("value"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "oil": self = .oil
        case "brakes": self = .brakes
        case "tires": self = .tires
        case "battery": self = .battery
        case "filters": self = .filters
        case "inspection": self = .inspection
        case "repair": self = .repair
        case "parts": self = .parts
        case "wash": self = .wash
        case "other": self = .other(try c.decode(String.self, forKey: key("value")))
        default: throw dataCorrupted("Unknown serviceCategory tag")
        }
    }
}

extension ExpenseCategory {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .insurance: try c.encode("insurance", forKey: key("tag"))
        case .tax: try c.encode("tax", forKey: key("tag"))
        case .parking: try c.encode("parking", forKey: key("tag"))
        case .toll: try c.encode("toll", forKey: key("tag"))
        case .fine: try c.encode("fine", forKey: key("tag"))
        case .accessory: try c.encode("accessory", forKey: key("tag"))
        case .parts: try c.encode("parts", forKey: key("tag"))
        case .other(let value):
            try c.encode("other", forKey: key("tag"))
            try c.encode(value, forKey: key("value"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "insurance": self = .insurance
        case "tax": self = .tax
        case "parking": self = .parking
        case "toll": self = .toll
        case "fine": self = .fine
        case "accessory": self = .accessory
        case "parts": self = .parts
        case "other": self = .other(try c.decode(String.self, forKey: key("value")))
        default: throw dataCorrupted("Unknown expenseCategory tag")
        }
    }
}

extension ReminderCategory {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .oil: try c.encode("oil", forKey: key("tag"))
        case .brakes: try c.encode("brakes", forKey: key("tag"))
        case .tires: try c.encode("tires", forKey: key("tag"))
        case .battery: try c.encode("battery", forKey: key("tag"))
        case .filters: try c.encode("filters", forKey: key("tag"))
        case .inspection: try c.encode("inspection", forKey: key("tag"))
        case .repair: try c.encode("repair", forKey: key("tag"))
        case .parts: try c.encode("parts", forKey: key("tag"))
        case .wash: try c.encode("wash", forKey: key("tag"))
        case .insurance: try c.encode("insurance", forKey: key("tag"))
        case .custom: try c.encode("custom", forKey: key("tag"))
        case .other(let value):
            try c.encode("other", forKey: key("tag"))
            try c.encode(value, forKey: key("value"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "oil": self = .oil
        case "brakes": self = .brakes
        case "tires": self = .tires
        case "battery": self = .battery
        case "filters": self = .filters
        case "inspection": self = .inspection
        case "repair": self = .repair
        case "parts": self = .parts
        case "wash": self = .wash
        case "insurance": self = .insurance
        case "custom": self = .custom
        case "other": self = .other(try c.decode(String.self, forKey: key("value")))
        default: throw dataCorrupted("Unknown reminderCategory tag")
        }
    }
}

extension ReminderStatus {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        switch self {
        case .scheduled:
            try c.encode("scheduled", forKey: key("tag"))
        case .attention:
            try c.encode("attention", forKey: key("tag"))
        case .done(let entryId):
            try c.encode("done", forKey: key("tag"))
            try c.encodeIfPresent(entryId, forKey: key("entryId"))
        case .dismissed(let reason):
            try c.encode("dismissed", forKey: key("tag"))
            try c.encodeIfPresent(reason, forKey: key("reason"))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        switch try c.decode(String.self, forKey: key("tag")) {
        case "scheduled": self = .scheduled
        case "attention": self = .attention
        case "done": self = .done(entryId: try c.decodeIfPresent(UUID.self, forKey: key("entryId")))
        case "dismissed": self = .dismissed(reason: try c.decodeIfPresent(String.self, forKey: key("reason")))
        default: throw dataCorrupted("Unknown reminderStatus tag")
        }
    }
}

// MARK: - FieldRef (a string, usable as a dictionary key)

extension FieldRef {
    /// Canonical string form: the case name for unit cases, `"lineItem(N)"` for
    /// line items. Stable across Swift, C# and SQL (docs/SCHEMA.md, FieldRef).
    var stringValue: String {
        switch self {
        case .total: return "total"
        case .volume: return "volume"
        case .unitPrice: return "unitPrice"
        case .date: return "date"
        case .station: return "station"
        case .fuelKind: return "fuelKind"
        case .energy: return "energy"
        case .currency: return "currency"
        case .vendor: return "vendor"
        case .lineItem(let n): return "lineItem(\(n))"
        }
    }

    init?(string: String) {
        switch string {
        case "total": self = .total
        case "volume": self = .volume
        case "unitPrice": self = .unitPrice
        case "date": self = .date
        case "station": self = .station
        case "fuelKind": self = .fuelKind
        case "energy": self = .energy
        case "currency": self = .currency
        case "vendor": self = .vendor
        default:
            if string.hasPrefix("lineItem("), string.hasSuffix(")"),
               let n = Int(string.dropFirst("lineItem(".count).dropLast()) {
                self = .lineItem(n)
            } else {
                return nil
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stringValue)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = FieldRef(string: raw) else {
            throw dataCorrupted("Unknown fieldRef '\(raw)'")
        }
        self = value
    }
}

// MARK: - ExtractionMeta (fields as a JSON object keyed by FieldRef strings)

extension ExtractionMeta {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        var fieldsContainer = c.nestedContainer(keyedBy: PayloadCodingKey.self, forKey: key("fields"))
        for (ref, extraction) in fields.sorted(by: { $0.key.stringValue < $1.key.stringValue }) {
            try fieldsContainer.encode(extraction, forKey: PayloadCodingKey(ref.stringValue))
        }
        try c.encode(pipeline, forKey: key("pipeline"))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        let fieldsContainer = try c.nestedContainer(keyedBy: PayloadCodingKey.self, forKey: key("fields"))
        var fields: [FieldRef: FieldExtraction] = [:]
        for fieldKey in fieldsContainer.allKeys {
            if let ref = FieldRef(string: fieldKey.stringValue) {
                fields[ref] = try fieldsContainer.decode(FieldExtraction.self, forKey: fieldKey)
            }
        }
        self.init(fields: fields, pipeline: try c.decode(String.self, forKey: key("pipeline")))
    }
}

// MARK: - FieldExtraction (flat normalized cropRect)

extension FieldExtraction {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        if let cropRect {
            var rectContainer = c.nestedContainer(keyedBy: PayloadCodingKey.self, forKey: key("cropRect"))
            try rectContainer.encode(cropRect.origin.x, forKey: key("x"))
            try rectContainer.encode(cropRect.origin.y, forKey: key("y"))
            try rectContainer.encode(cropRect.width, forKey: key("width"))
            try rectContainer.encode(cropRect.height, forKey: key("height"))
        }
        try c.encode(confidence, forKey: key("confidence"))
        try c.encode(userCorrected, forKey: key("userCorrected"))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        if c.contains(key("cropRect")) {
            let rectContainer = try c.nestedContainer(keyedBy: PayloadCodingKey.self, forKey: key("cropRect"))
            let x = try rectContainer.decode(Double.self, forKey: key("x"))
            let y = try rectContainer.decode(Double.self, forKey: key("y"))
            let width = try rectContainer.decode(Double.self, forKey: key("width"))
            let height = try rectContainer.decode(Double.self, forKey: key("height"))
            cropRect = CGRect(x: x, y: y, width: width, height: height)
        } else {
            cropRect = nil
        }
        confidence = try c.decode(Double.self, forKey: key("confidence"))
        userCorrected = try c.decode(Bool.self, forKey: key("userCorrected"))
    }
}

// MARK: - Entries with bare Decimal columns (decimals must be JSON strings)

/// `FiscalDocumentIdentity` is three decimal-digit strings. The synthesized
/// Codable shape `{ fiscalDriveNumber, documentNumber, fiscalSign }` is exactly
/// the payload contract, so this spells it out explicitly rather than relying on
/// synthesis - the type is declared in FiscalQR.swift, and Swift only synthesizes
/// conformance in the declaring file.
extension FiscalDocumentIdentity: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PayloadCodingKey.self)
        try container.encode(fiscalDriveNumber, forKey: PayloadCodingKey("fiscalDriveNumber"))
        try container.encode(documentNumber, forKey: PayloadCodingKey("documentNumber"))
        try container.encode(fiscalSign, forKey: PayloadCodingKey("fiscalSign"))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PayloadCodingKey.self)
        self.init(
            fiscalDriveNumber: try container.decode(String.self, forKey: PayloadCodingKey("fiscalDriveNumber")),
            documentNumber: try container.decode(String.self, forKey: PayloadCodingKey("documentNumber")),
            fiscalSign: try container.decode(String.self, forKey: PayloadCodingKey("fiscalSign")))
    }
}

extension FillUp {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        try c.encode(id, forKey: key("id"))
        try c.encode(PayloadFormat.dateString(createdAt), forKey: key("createdAt"))
        try c.encode(PayloadFormat.dateString(updatedAt), forKey: key("updatedAt"))
        try c.encodeIfPresent(deletedAt.map(PayloadFormat.dateString), forKey: key("deletedAt"))
        try c.encode(vehicleId, forKey: key("vehicleId"))
        try c.encode(PayloadFormat.dateString(date), forKey: key("date"))
        try c.encodeIfPresent(odometer, forKey: key("odometer"))
        try c.encodeIfPresent(money, forKey: key("money"))
        try c.encodeIfPresent(note, forKey: key("note"))
        try c.encode(attachments, forKey: key("attachments"))
        try c.encode(provenance, forKey: key("provenance"))
        try c.encode(conflict, forKey: key("conflict"))
        try c.encodeIfPresent(purchaseGroupId, forKey: key("purchaseGroupId"))
        try c.encode(volumeL, forKey: key("volumeL"))
        try c.encodeIfPresent(unitPrice.map(PayloadFormat.decimalString), forKey: key("unitPrice"))
        try c.encode(fuelKind, forKey: key("fuelKind"))
        try c.encodeIfPresent(fuelGrade, forKey: key("fuelGrade"))
        try c.encode(isFull, forKey: key("isFull"))
        try c.encodeIfPresent(tankLevelAfterPct, forKey: key("tankLevelAfterPct"))
        try c.encodeIfPresent(stationId, forKey: key("stationId"))
        try c.encode(crossCheck, forKey: key("crossCheck"))
        try c.encodeIfPresent(extraction, forKey: key("extraction"))
        try c.encodeIfPresent(fiscalIdentity, forKey: key("fiscalIdentity"))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        func date(_ k: String) throws -> Date {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)),
                  let value = PayloadFormat.date(from: raw) else {
                throw dataCorrupted("Invalid date for \(k)")
            }
            return value
        }
        func optionalDate(_ k: String) throws -> Date? {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)) else { return nil }
            guard let value = PayloadFormat.date(from: raw) else { throw dataCorrupted("Invalid date for \(k)") }
            return value
        }
        func optionalDecimal(_ k: String) throws -> Decimal? {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)) else { return nil }
            guard let value = PayloadFormat.decimal(from: raw) else { throw dataCorrupted("Invalid decimal for \(k)") }
            return value
        }
        self.init(
            id: try c.decode(UUID.self, forKey: key("id")),
            createdAt: try date("createdAt"),
            updatedAt: try date("updatedAt"),
            deletedAt: try optionalDate("deletedAt"),
            vehicleId: try c.decode(UUID.self, forKey: key("vehicleId")),
            date: try date("date"),
            odometer: try c.decodeIfPresent(Int.self, forKey: key("odometer")),
            money: try c.decodeIfPresent(Money.self, forKey: key("money")),
            note: try c.decodeIfPresent(String.self, forKey: key("note")),
            attachments: try c.decode([AttachmentID].self, forKey: key("attachments")),
            provenance: try c.decode(Provenance.self, forKey: key("provenance")),
            conflict: try c.decode(ConflictState.self, forKey: key("conflict")),
            purchaseGroupId: try c.decodeIfPresent(UUID.self, forKey: key("purchaseGroupId")),
            volumeL: try c.decode(Double.self, forKey: key("volumeL")),
            unitPrice: try optionalDecimal("unitPrice"),
            fuelKind: try c.decode(FuelKind.self, forKey: key("fuelKind")),
            fuelGrade: try c.decodeIfPresent(String.self, forKey: key("fuelGrade")),
            isFull: try c.decode(Bool.self, forKey: key("isFull")),
            tankLevelAfterPct: try c.decodeIfPresent(Double.self, forKey: key("tankLevelAfterPct")),
            stationId: try c.decodeIfPresent(UUID.self, forKey: key("stationId")),
            crossCheck: try c.decode(CrossCheckState.self, forKey: key("crossCheck")),
            extraction: try c.decodeIfPresent(ExtractionMeta.self, forKey: key("extraction")),
            fiscalIdentity: try c.decodeIfPresent(FiscalDocumentIdentity.self, forKey: key("fiscalIdentity"))
        )
    }
}

extension ChargeSession {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        try c.encode(id, forKey: key("id"))
        try c.encode(PayloadFormat.dateString(createdAt), forKey: key("createdAt"))
        try c.encode(PayloadFormat.dateString(updatedAt), forKey: key("updatedAt"))
        try c.encodeIfPresent(deletedAt.map(PayloadFormat.dateString), forKey: key("deletedAt"))
        try c.encode(vehicleId, forKey: key("vehicleId"))
        try c.encode(PayloadFormat.dateString(date), forKey: key("date"))
        try c.encodeIfPresent(odometer, forKey: key("odometer"))
        try c.encodeIfPresent(money, forKey: key("money"))
        try c.encodeIfPresent(note, forKey: key("note"))
        try c.encode(attachments, forKey: key("attachments"))
        try c.encode(provenance, forKey: key("provenance"))
        try c.encode(conflict, forKey: key("conflict"))
        try c.encodeIfPresent(purchaseGroupId, forKey: key("purchaseGroupId"))
        try c.encode(energyKWh, forKey: key("energyKWh"))
        try c.encodeIfPresent(unitPrice.map(PayloadFormat.decimalString), forKey: key("unitPrice"))
        try c.encode(chargeType, forKey: key("chargeType"))
        try c.encodeIfPresent(provider, forKey: key("provider"))
        try c.encodeIfPresent(tariffId, forKey: key("tariffId"))
        try c.encodeIfPresent(durationMin, forKey: key("durationMin"))
        try c.encodeIfPresent(socStartPct, forKey: key("socStartPct"))
        try c.encodeIfPresent(socEndPct, forKey: key("socEndPct"))
        try c.encodeIfPresent(extraction, forKey: key("extraction"))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        func date(_ k: String) throws -> Date {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)),
                  let value = PayloadFormat.date(from: raw) else {
                throw dataCorrupted("Invalid date for \(k)")
            }
            return value
        }
        func optionalDate(_ k: String) throws -> Date? {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)) else { return nil }
            guard let value = PayloadFormat.date(from: raw) else { throw dataCorrupted("Invalid date for \(k)") }
            return value
        }
        func optionalDecimal(_ k: String) throws -> Decimal? {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)) else { return nil }
            guard let value = PayloadFormat.decimal(from: raw) else { throw dataCorrupted("Invalid decimal for \(k)") }
            return value
        }
        self.init(
            id: try c.decode(UUID.self, forKey: key("id")),
            createdAt: try date("createdAt"),
            updatedAt: try date("updatedAt"),
            deletedAt: try optionalDate("deletedAt"),
            vehicleId: try c.decode(UUID.self, forKey: key("vehicleId")),
            date: try date("date"),
            odometer: try c.decodeIfPresent(Int.self, forKey: key("odometer")),
            money: try c.decodeIfPresent(Money.self, forKey: key("money")),
            note: try c.decodeIfPresent(String.self, forKey: key("note")),
            attachments: try c.decode([AttachmentID].self, forKey: key("attachments")),
            provenance: try c.decode(Provenance.self, forKey: key("provenance")),
            conflict: try c.decode(ConflictState.self, forKey: key("conflict")),
            purchaseGroupId: try c.decodeIfPresent(UUID.self, forKey: key("purchaseGroupId")),
            energyKWh: try c.decode(Double.self, forKey: key("energyKWh")),
            unitPrice: try optionalDecimal("unitPrice"),
            chargeType: try c.decode(ChargeType.self, forKey: key("chargeType")),
            provider: try c.decodeIfPresent(String.self, forKey: key("provider")),
            tariffId: try c.decodeIfPresent(UUID.self, forKey: key("tariffId")),
            durationMin: try c.decodeIfPresent(Int.self, forKey: key("durationMin")),
            socStartPct: try c.decodeIfPresent(Double.self, forKey: key("socStartPct")),
            socEndPct: try c.decodeIfPresent(Double.self, forKey: key("socEndPct")),
            extraction: try c.decodeIfPresent(ExtractionMeta.self, forKey: key("extraction"))
        )
    }
}

extension Tariff {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadCodingKey.self)
        try c.encode(id, forKey: key("id"))
        try c.encode(PayloadFormat.dateString(createdAt), forKey: key("createdAt"))
        try c.encode(PayloadFormat.dateString(updatedAt), forKey: key("updatedAt"))
        try c.encodeIfPresent(deletedAt.map(PayloadFormat.dateString), forKey: key("deletedAt"))
        try c.encodeIfPresent(vehicleId, forKey: key("vehicleId"))
        try c.encode(name, forKey: key("name"))
        try c.encode(PayloadFormat.decimalString(pricePerKWh), forKey: key("pricePerKWh"))
        try c.encode(currency, forKey: key("currency"))
        try c.encode(PayloadFormat.dateString(validFrom), forKey: key("validFrom"))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PayloadCodingKey.self)
        func date(_ k: String) throws -> Date {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)),
                  let value = PayloadFormat.date(from: raw) else {
                throw dataCorrupted("Invalid date for \(k)")
            }
            return value
        }
        func optionalDate(_ k: String) throws -> Date? {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key(k)) else { return nil }
            guard let value = PayloadFormat.date(from: raw) else { throw dataCorrupted("Invalid date for \(k)") }
            return value
        }
        guard let price = try c.decode(String.self, forKey: key("pricePerKWh")).withPayloadDecimal else {
            throw dataCorrupted("Invalid decimal for pricePerKWh")
        }
        self.init(
            id: try c.decode(UUID.self, forKey: key("id")),
            createdAt: try date("createdAt"),
            updatedAt: try date("updatedAt"),
            deletedAt: try optionalDate("deletedAt"),
            vehicleId: try c.decodeIfPresent(UUID.self, forKey: key("vehicleId")),
            name: try c.decode(String.self, forKey: key("name")),
            pricePerKWh: price,
            currency: try c.decode(CurrencyCode.self, forKey: key("currency")),
            validFrom: try date("validFrom")
        )
    }
}
