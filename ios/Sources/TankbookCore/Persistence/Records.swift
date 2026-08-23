import Foundation
import GRDB

// Record conformances map the pure domain types (Sources/TankbookCore/Domain/)
// to the SQLite schema from Migrations.swift. The domain structs stay free of
// GRDB imports; each `*Row` here is a thin wrapper around a domain value plus
// the sync bookkeeping (syncState/syncScn). The wrapper adds the envelope and
// money columns that the domain protocol cannot represent.
//
// Money columns are flattened (docs/SCHEMA.md, Money): amount/currency/
// homeAmount/homeCurrency/rate/rateDate/rateSource. Dates are REAL Unix
// timestamps and Decimals are TEXT - both exact round-trips (see the storage
// conventions comment in Migrations.swift).

// MARK: - Shared helpers

struct Envelope {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

func decodeEnvelope(_ row: Row) throws -> Envelope {
    guard let id = UUID(uuidString: row["id"] as String) else {
        throw DatabaseError(message: "TankbookCore: invalid UUID in 'id' column")
    }
    return Envelope(
        id: id,
        createdAt: Date(timeIntervalSince1970: row["createdAt"] as Double),
        updatedAt: Date(timeIntervalSince1970: row["updatedAt"] as Double),
        deletedAt: (row["deletedAt"] as Double?).map(Date.init(timeIntervalSince1970:)))
}

func setEnvelope<Value: Entity>(_ value: Value, into container: inout PersistenceContainer) {
    container["id"] = value.id.uuidString
    container["createdAt"] = value.createdAt.timeIntervalSince1970
    container["updatedAt"] = value.updatedAt.timeIntervalSince1970
    container["deletedAt"] = value.deletedAt?.timeIntervalSince1970
}

func decodeSync(_ row: Row) -> (state: SyncState, scn: Int64?) {
    let scn: Int64? = row["syncScn"]
    var state = SyncState(storageValue: row["syncState"] as String)
    if case .synced = state {
        state = .synced(scn: scn)
    }
    return (state, scn)
}

func setSync(_ state: SyncState, scn: Int64?, into container: inout PersistenceContainer) {
    container["syncState"] = state.storageValue
    container["syncScn"] = scn
}

func scn(for state: SyncState) -> Int64? {
    if case .synced(let scn) = state { return scn }
    return nil
}

func encodeJSON(_ value: some Encodable) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw DatabaseError(message: "TankbookCore: could not encode JSON")
    }
    return string
}

func decodeJSON<T: Decodable>(_ type: T.Type, from row: Row, column: String) throws -> T {
    let string = row[column] as String
    guard let data = string.data(using: .utf8),
          let value = try? JSONDecoder().decode(type, from: data) else {
        throw DatabaseError(message: "TankbookCore: could not decode JSON in column '\(column)'")
    }
    return value
}

func decodeCurrency(_ row: Row, column: String) throws -> CurrencyCode {
    guard let code = CurrencyCode(rawValue: row[column] as String) else {
        throw DatabaseError(message: "TankbookCore: invalid currency in column '\(column)'")
    }
    return code
}

func decodeOptionalUUID(_ row: Row, column: String) -> UUID? {
    (row[column] as String?).flatMap(UUID.init(uuidString:))
}

// MARK: - Money

func setMoney(_ money: Money?, into container: inout PersistenceContainer, prefix: String = "") {
    guard let money else {
        for base in ["amount", "currency", "homeAmount", "homeCurrency", "rate"] {
            container[TankbookSchema.moneyColumn(prefix, base)] = nil as Decimal?
        }
        container[TankbookSchema.moneyColumn(prefix, "rateDate")] = nil as Double?
        container[TankbookSchema.moneyColumn(prefix, "rateSource")] = nil as String?
        return
    }
    container[TankbookSchema.moneyColumn(prefix, "amount")] = money.amount
    container[TankbookSchema.moneyColumn(prefix, "currency")] = money.currency.rawValue
    container[TankbookSchema.moneyColumn(prefix, "homeAmount")] = money.homeAmount
    container[TankbookSchema.moneyColumn(prefix, "homeCurrency")] = money.homeCurrency.rawValue
    container[TankbookSchema.moneyColumn(prefix, "rate")] = money.rate
    container[TankbookSchema.moneyColumn(prefix, "rateDate")] = money.rateDate?.timeIntervalSince1970
    container[TankbookSchema.moneyColumn(prefix, "rateSource")] = money.rateSource.rawValue
}

/// Reconstructs a `Money` from its flattened columns. A cross-currency snapshot
/// is rebuilt through `converted(using:)` - the very operation that produced it
/// - so the stored `homeAmount`/`rate`/`rateDate`/`rateSource` are reproduced
/// exactly. Same-currency money and rate-pending money are both produced by the
/// plain initializer, which matches how they were created.
func decodeMoney(_ row: Row, prefix: String = "") throws -> Money? {
    guard let amount = row[TankbookSchema.moneyColumn(prefix, "amount")] as Decimal?,
          let currency = try? decodeCurrency(row, column: TankbookSchema.moneyColumn(prefix, "currency")),
          let homeCurrency = try? decodeCurrency(row, column: TankbookSchema.moneyColumn(prefix, "homeCurrency")) else {
        // Absent money columns (all NULL) mean the entry is a free event.
        return nil
    }
    var money = Money(amount: amount, currency: currency, homeCurrency: homeCurrency)
    if currency != homeCurrency,
       row[TankbookSchema.moneyColumn(prefix, "homeAmount")] as Decimal? != nil,
       let rate = row[TankbookSchema.moneyColumn(prefix, "rate")] as Decimal?,
       let rateDate = (row[TankbookSchema.moneyColumn(prefix, "rateDate")] as Double?).map(Date.init(timeIntervalSince1970:)) {
        let source = (row[TankbookSchema.moneyColumn(prefix, "rateSource")] as String?)
            .flatMap(RateSource.init(rawValue:)) ?? .ecb
        money = money.converted(using: RateSnapshot(rate: rate, rateDate: rateDate, source: source))
    }
    return money
}

// MARK: - EntryCommon

struct EntryCommonParts {
    var envelope: Envelope
    var vehicleId: UUID
    var date: Date
    var odometer: Int?
    var money: Money?
    var note: String?
    var attachments: [AttachmentID]
    var provenance: Provenance
    var conflict: ConflictState
    var purchaseGroupId: UUID?
}

func setEntryCommon<Value: Entry>(_ value: Value, into container: inout PersistenceContainer) throws {
    setEnvelope(value, into: &container)
    container["vehicleId"] = value.vehicleId.uuidString
    container["date"] = value.date.timeIntervalSince1970
    container["odometer"] = value.odometer
    setMoney(value.money, into: &container)
    container["note"] = value.note
    container["provenance"] = try encodeJSON(value.provenance)
    container["conflict"] = try encodeJSON(value.conflict)
    container["purchaseGroupId"] = value.purchaseGroupId?.uuidString
    container["attachments"] = try encodeJSON(value.attachments)
}

func decodeEntryCommon(_ row: Row) throws -> EntryCommonParts {
    guard let vehicleId = UUID(uuidString: row["vehicleId"] as String) else {
        throw DatabaseError(message: "TankbookCore: invalid UUID in 'vehicleId' column")
    }
    return EntryCommonParts(
        envelope: try decodeEnvelope(row),
        vehicleId: vehicleId,
        date: Date(timeIntervalSince1970: row["date"] as Double),
        odometer: row["odometer"] as Int?,
        money: try decodeMoney(row),
        note: row["note"] as String?,
        attachments: try decodeJSON([UUID].self, from: row, column: "attachments"),
        provenance: try decodeJSON(Provenance.self, from: row, column: "provenance"),
        conflict: try decodeJSON(ConflictState.self, from: row, column: "conflict"),
        purchaseGroupId: decodeOptionalUUID(row, column: "purchaseGroupId"))
}

func encodeOptionalJSON(_ value: (some Encodable)?) throws -> String? {
    guard let value else { return nil }
    return try encodeJSON(value)
}

func decodeOptionalJSON<T: Decodable>(_ type: T.Type, from row: Row, column: String) throws -> T? {
    guard (row[column] as String?) != nil else { return nil }
    return try decodeJSON(type, from: row, column: column)
}

// MARK: - Vehicle

public struct VehicleRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.vehicle
    public var vehicle: Vehicle
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(vehicle: Vehicle, syncState: SyncState = .dirty) {
        self.vehicle = vehicle
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        vehicle = Vehicle(
            id: envelope.id,
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            name: row["name"],
            make: row["make"] as String?,
            model: row["model"] as String?,
            year: row["year"] as Int?,
            plate: row["plate"] as String?,
            powertrain: Powertrain(rawValue: row["powertrain"]) ?? .ice,
            fuelKinds: try decodeJSON([FuelKind].self, from: row, column: "fuelKinds"),
            tankCapacityL: row["tankCapacityL"] as Double?,
            batteryCapacityKWh: row["batteryCapacityKWh"] as Double?,
            homeCurrency: try decodeCurrency(row, column: "homeCurrency"),
            units: Vehicle.Units(
                distance: DistanceUnit(rawValue: row["distanceUnit"]) ?? .km,
                volume: VolumeUnit(rawValue: row["volumeUnit"]) ?? .l,
                consumption: ConsumptionUnit(rawValue: row["consumptionUnit"]) ?? .lPer100,
                energy: EnergyUnit(rawValue: row["energyUnit"]) ?? .kWhPer100),
            photo: decodeOptionalUUID(row, column: "photo"),
            archived: row["archived"] as Bool,
            paceLimitKmPerDay: row["paceLimitKmPerDay"] as Double,
            initialOdometer: row["initialOdometer"] as Int?)
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(vehicle, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["name"] = vehicle.name
        container["make"] = vehicle.make
        container["model"] = vehicle.model
        container["year"] = vehicle.year
        container["plate"] = vehicle.plate
        container["powertrain"] = vehicle.powertrain.rawValue
        container["fuelKinds"] = try encodeJSON(vehicle.fuelKinds)
        container["tankCapacityL"] = vehicle.tankCapacityL
        container["batteryCapacityKWh"] = vehicle.batteryCapacityKWh
        container["homeCurrency"] = vehicle.homeCurrency.rawValue
        container["distanceUnit"] = vehicle.units.distance.rawValue
        container["volumeUnit"] = vehicle.units.volume.rawValue
        container["consumptionUnit"] = vehicle.units.consumption.rawValue
        container["energyUnit"] = vehicle.units.energy.rawValue
        container["photo"] = vehicle.photo?.uuidString
        container["archived"] = vehicle.archived
        container["paceLimitKmPerDay"] = vehicle.paceLimitKmPerDay
        container["initialOdometer"] = vehicle.initialOdometer
    }
}

// MARK: - FillUp

public struct FillUpRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.fillUp
    public var fillUp: FillUp
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(fillUp: FillUp, syncState: SyncState = .dirty) {
        self.fillUp = fillUp
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let common = try decodeEntryCommon(row)
        fillUp = FillUp(
            id: common.envelope.id,
            createdAt: common.envelope.createdAt,
            updatedAt: common.envelope.updatedAt,
            deletedAt: common.envelope.deletedAt,
            vehicleId: common.vehicleId,
            date: common.date,
            odometer: common.odometer,
            money: common.money,
            note: common.note,
            attachments: common.attachments,
            provenance: common.provenance,
            conflict: common.conflict,
            purchaseGroupId: common.purchaseGroupId,
            volumeL: row["volumeL"] as Double,
            unitPrice: row["unitPrice"] as Decimal?,
            fuelKind: FuelKind(rawValue: row["fuelKind"]) ?? .petrol95,
            fuelGrade: row["fuelGrade"] as String?,
            isFull: row["isFull"] as Bool,
            tankLevelAfterPct: row["tankLevelAfterPct"] as Double?,
            stationId: decodeOptionalUUID(row, column: "stationId"),
            crossCheck: try decodeJSON(CrossCheckState.self, from: row, column: "crossCheck"),
            extraction: try decodeOptionalJSON(ExtractionMeta.self, from: row, column: "extraction"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        try setEntryCommon(fillUp, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["volumeL"] = fillUp.volumeL
        container["unitPrice"] = fillUp.unitPrice
        container["fuelKind"] = fillUp.fuelKind.rawValue
        container["fuelGrade"] = fillUp.fuelGrade
        container["isFull"] = fillUp.isFull
        container["tankLevelAfterPct"] = fillUp.tankLevelAfterPct
        container["stationId"] = fillUp.stationId?.uuidString
        container["crossCheck"] = try encodeJSON(fillUp.crossCheck)
        container["extraction"] = try encodeOptionalJSON(fillUp.extraction)
    }
}

// MARK: - ChargeSession

public struct ChargeSessionRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.chargeSession
    public var chargeSession: ChargeSession
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(chargeSession: ChargeSession, syncState: SyncState = .dirty) {
        self.chargeSession = chargeSession
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let common = try decodeEntryCommon(row)
        chargeSession = ChargeSession(
            id: common.envelope.id,
            createdAt: common.envelope.createdAt,
            updatedAt: common.envelope.updatedAt,
            deletedAt: common.envelope.deletedAt,
            vehicleId: common.vehicleId,
            date: common.date,
            odometer: common.odometer,
            money: common.money,
            note: common.note,
            attachments: common.attachments,
            provenance: common.provenance,
            conflict: common.conflict,
            purchaseGroupId: common.purchaseGroupId,
            energyKWh: row["energyKWh"] as Double,
            unitPrice: row["unitPrice"] as Decimal?,
            chargeType: ChargeType(rawValue: row["chargeType"]) ?? .acPublic,
            provider: row["provider"] as String?,
            tariffId: decodeOptionalUUID(row, column: "tariffId"),
            durationMin: row["durationMin"] as Int?,
            socStartPct: row["socStartPct"] as Double?,
            socEndPct: row["socEndPct"] as Double?,
            extraction: try decodeOptionalJSON(ExtractionMeta.self, from: row, column: "extraction"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        try setEntryCommon(chargeSession, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["energyKWh"] = chargeSession.energyKWh
        container["unitPrice"] = chargeSession.unitPrice
        container["chargeType"] = chargeSession.chargeType.rawValue
        container["provider"] = chargeSession.provider
        container["tariffId"] = chargeSession.tariffId?.uuidString
        container["durationMin"] = chargeSession.durationMin
        container["socStartPct"] = chargeSession.socStartPct
        container["socEndPct"] = chargeSession.socEndPct
        container["extraction"] = try encodeOptionalJSON(chargeSession.extraction)
    }
}

// MARK: - ServiceRecord + ServiceItem

/// `ServiceRecord.items` lives in the normalized `serviceItem` child table; a
/// single row cannot carry the child rows, so `init(row:)` leaves `items`
/// empty and the repository attaches them (see `loadServiceItems`).
public struct ServiceRecordRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.serviceRecord
    public var service: ServiceRecord
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(service: ServiceRecord, syncState: SyncState = .dirty) {
        self.service = service
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let common = try decodeEntryCommon(row)
        service = ServiceRecord(
            id: common.envelope.id,
            createdAt: common.envelope.createdAt,
            updatedAt: common.envelope.updatedAt,
            deletedAt: common.envelope.deletedAt,
            vehicleId: common.vehicleId,
            date: common.date,
            odometer: common.odometer,
            money: common.money,
            note: common.note,
            attachments: common.attachments,
            provenance: common.provenance,
            conflict: common.conflict,
            purchaseGroupId: common.purchaseGroupId,
            vendor: row["vendor"] as String?,
            items: [],
            usedParts: try decodeJSON([UUID].self, from: row, column: "usedParts"),
            tireSetId: decodeOptionalUUID(row, column: "tireSetId"),
            proposedReminderId: decodeOptionalUUID(row, column: "proposedReminderId"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        try setEntryCommon(service, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["vendor"] = service.vendor
        container["usedParts"] = try encodeJSON(service.usedParts)
        container["tireSetId"] = service.tireSetId?.uuidString
        container["proposedReminderId"] = service.proposedReminderId?.uuidString
    }
}

public struct ServiceItemRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.serviceItem
    public var serviceRecordId: UUID
    public var position: Int
    public var item: ServiceItem

    public init(serviceRecordId: UUID, position: Int, item: ServiceItem) {
        self.serviceRecordId = serviceRecordId
        self.position = position
        self.item = item
    }

    public init(row: Row) throws {
        guard let serviceRecordId = UUID(uuidString: row["serviceRecordId"] as String) else {
            throw DatabaseError(message: "TankbookCore: invalid UUID in 'serviceRecordId' column")
        }
        self.serviceRecordId = serviceRecordId
        position = row["position"] as Int
        item = ServiceItem(
            title: row["title"],
            category: try decodeJSON(ServiceCategory.self, from: row, column: "category"),
            cost: try decodeMoney(row, prefix: "cost"),
            partNumber: row["partNumber"] as String?,
            lifetime: try decodeOptionalJSON(ServiceItem.Lifetime.self, from: row, column: "lifetime"))
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["serviceRecordId"] = serviceRecordId.uuidString
        container["position"] = position
        container["title"] = item.title
        container["category"] = try encodeJSON(item.category)
        setMoney(item.cost, into: &container, prefix: "cost")
        container["partNumber"] = item.partNumber
        container["lifetime"] = try encodeOptionalJSON(item.lifetime)
    }
}

// MARK: - Expense

public struct ExpenseRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.expense
    public var expense: Expense
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(expense: Expense, syncState: SyncState = .dirty) {
        self.expense = expense
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let common = try decodeEntryCommon(row)
        expense = Expense(
            id: common.envelope.id,
            createdAt: common.envelope.createdAt,
            updatedAt: common.envelope.updatedAt,
            deletedAt: common.envelope.deletedAt,
            vehicleId: common.vehicleId,
            date: common.date,
            odometer: common.odometer,
            money: common.money,
            note: common.note,
            attachments: common.attachments,
            provenance: common.provenance,
            conflict: common.conflict,
            purchaseGroupId: common.purchaseGroupId,
            category: try decodeJSON(ExpenseCategory.self, from: row, column: "category"),
            title: row["title"],
            recurrence: try decodeOptionalJSON(RecurrenceRule.self, from: row, column: "recurrence"),
            installedInServiceId: decodeOptionalUUID(row, column: "installedInServiceId"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        try setEntryCommon(expense, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["category"] = try encodeJSON(expense.category)
        container["title"] = expense.title
        container["recurrence"] = try encodeOptionalJSON(expense.recurrence)
        container["installedInServiceId"] = expense.installedInServiceId?.uuidString
    }
}

