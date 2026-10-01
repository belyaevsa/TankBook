import Foundation

/// A diesel-exhaust-fluid top-up (docs/SCHEMA.md, AdBlueFill). Its own entity,
/// not a `FillUp` kind: no fuel reader can count it, and a build that does not
/// know the entity type skips it on pull instead of failing to decode a fuel
/// kind it has never seen (docs/API.md -> breaking-change notes). Its money is
/// car money; its litres feed only `AdBlueStats`.
public struct AdBlueFill: Entry, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var vehicleId: UUID
    public var date: Date
    public var odometer: Int?
    public var money: Money?
    public var note: String?
    public var attachments: [AttachmentID]
    public var provenance: Provenance
    public var conflict: ConflictState
    public var flagAcceptance: FlagAcceptance?
    public var purchaseGroupId: UUID?
    public var volumeL: Double
    public var unitPrice: Decimal?
    public var stationId: UUID?

    public init(id: UUID, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil,
                vehicleId: UUID, date: Date, odometer: Int? = nil, money: Money? = nil,
                note: String? = nil, attachments: [AttachmentID] = [],
                provenance: Provenance, conflict: ConflictState = .none,
                flagAcceptance: FlagAcceptance? = nil, purchaseGroupId: UUID? = nil,
                volumeL: Double, unitPrice: Decimal? = nil, stationId: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.vehicleId = vehicleId
        self.date = date
        self.odometer = odometer
        self.money = money
        self.note = note
        self.attachments = attachments
        self.provenance = provenance
        self.conflict = conflict
        self.flagAcceptance = flagAcceptance
        self.purchaseGroupId = purchaseGroupId
        self.volumeL = volumeL
        self.unitPrice = unitPrice
        self.stationId = stationId
    }
}

extension AdBlueFill {
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
        try c.encodeIfPresent(stationId, forKey: key("stationId"))
        try c.encodeIfPresent(flagAcceptance, forKey: key("flagAcceptance"))
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
        var unitPrice: Decimal?
        if let raw = try c.decodeIfPresent(String.self, forKey: key("unitPrice")) {
            guard let value = PayloadFormat.decimal(from: raw) else { throw dataCorrupted("Invalid decimal for unitPrice") }
            unitPrice = value
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
            flagAcceptance: try c.decodeIfPresent(FlagAcceptance.self, forKey: key("flagAcceptance")),
            purchaseGroupId: try c.decodeIfPresent(UUID.self, forKey: key("purchaseGroupId")),
            volumeL: try c.decode(Double.self, forKey: key("volumeL")),
            unitPrice: unitPrice,
            stationId: try c.decodeIfPresent(UUID.self, forKey: key("stationId"))
        )
    }
}
