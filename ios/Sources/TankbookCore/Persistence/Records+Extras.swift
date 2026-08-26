import Foundation
import GRDB

// Non-entry records. The shared mapping helpers live in Records.swift.

// MARK: - Reminder

public struct ReminderRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.reminder
    public var reminder: Reminder
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(reminder: Reminder, syncState: SyncState = .dirty) {
        self.reminder = reminder
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        guard let vehicleId = UUID(uuidString: row["vehicleId"] as String) else {
            throw DatabaseError(message: "TankbookCore: invalid UUID in 'vehicleId' column")
        }
        reminder = Reminder(
            id: envelope.id,
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            vehicleId: vehicleId,
            title: row["title"],
            category: try decodeJSON(ReminderCategory.self, from: row, column: "category"),
            dueDate: (row["dueDate"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
            dueOdometer: row["dueOdometer"] as Int?,
            recurrence: try decodeOptionalJSON(Reminder.Recurrence.self, from: row, column: "recurrence"),
            sourceEntryId: decodeOptionalUUID(row, column: "sourceEntryId"),
            status: try decodeJSON(ReminderStatus.self, from: row, column: "status"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(reminder, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["vehicleId"] = reminder.vehicleId.uuidString
        container["title"] = reminder.title
        container["category"] = try encodeJSON(reminder.category)
        container["dueDate"] = reminder.dueDate?.timeIntervalSinceReferenceDate
        container["dueOdometer"] = reminder.dueOdometer
        container["recurrence"] = try encodeOptionalJSON(reminder.recurrence)
        container["sourceEntryId"] = reminder.sourceEntryId?.uuidString
        container["status"] = try encodeJSON(reminder.status)
    }
}

// MARK: - Station

public struct StationRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.station
    public var station: Station
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(station: Station, syncState: SyncState = .dirty) {
        self.station = station
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        let latitude = row["locationLat"] as Double?
        let longitude = row["locationLng"] as Double?
        station = Station(
            id: envelope.id,
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            name: row["name"],
            brand: row["brand"] as String?,
            location: (latitude != nil && longitude != nil)
                ? GeoCoordinate(latitude: latitude!, longitude: longitude!) : nil,
            favorite: row["favorite"] as Bool,
            defaults: try decodeJSON(Station.Defaults.self, from: row, column: "defaults"),
            lastUsedAt: (row["lastUsedAt"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(station, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["name"] = station.name
        container["brand"] = station.brand
        container["locationLat"] = station.location?.latitude
        container["locationLng"] = station.location?.longitude
        container["favorite"] = station.favorite
        container["defaults"] = try encodeJSON(station.defaults)
        container["lastUsedAt"] = station.lastUsedAt?.timeIntervalSinceReferenceDate
    }
}

// MARK: - Tariff

public struct TariffRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.tariff
    public var tariff: Tariff
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(tariff: Tariff, syncState: SyncState = .dirty) {
        self.tariff = tariff
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        tariff = Tariff(
            id: envelope.id,
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            vehicleId: decodeOptionalUUID(row, column: "vehicleId"),
            name: row["name"],
            pricePerKWh: row["pricePerKWh"] as Decimal,
            currency: try decodeCurrency(row, column: "currency"),
            validFrom: Date(timeIntervalSinceReferenceDate: row["validFrom"] as Double))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(tariff, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["vehicleId"] = tariff.vehicleId?.uuidString
        container["name"] = tariff.name
        container["pricePerKWh"] = tariff.pricePerKWh
        container["currency"] = tariff.currency.rawValue
        container["validFrom"] = tariff.validFrom.timeIntervalSinceReferenceDate
    }
}

// MARK: - TireSet

public struct TireSetRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.tireSet
    public var tireSet: TireSet
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(tireSet: TireSet, syncState: SyncState = .dirty) {
        self.tireSet = tireSet
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        guard let vehicleId = UUID(uuidString: row["vehicleId"] as String) else {
            throw DatabaseError(message: "TankbookCore: invalid UUID in 'vehicleId' column")
        }
        tireSet = TireSet(
            id: envelope.id,
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            vehicleId: vehicleId,
            name: row["name"],
            purchaseExpenseId: decodeOptionalUUID(row, column: "purchaseExpenseId"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(tireSet, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["vehicleId"] = tireSet.vehicleId.uuidString
        container["name"] = tireSet.name
        container["purchaseExpenseId"] = tireSet.purchaseExpenseId?.uuidString
    }
}

// MARK: - Attachment

public struct AttachmentRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.attachment
    public var attachment: Attachment
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(attachment: Attachment, syncState: SyncState = .dirty) {
        self.attachment = attachment
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        attachment = Attachment(
            id: envelope.id,
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            kind: AttachmentKind(rawValue: row["kind"]) ?? .photo,
            file: LocalFileRef(
                sha256: row["fileSha256"],
                relativePath: row["fileRelativePath"]),
            extractedTimestamp: (row["extractedTimestamp"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
            ocrText: row["ocrText"] as String?,
            thumbnailBase64: row["thumbnailBase64"] as String?)
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(attachment, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["kind"] = attachment.kind.rawValue
        container["fileSha256"] = attachment.file.sha256
        container["fileRelativePath"] = attachment.file.relativePath
        container["extractedTimestamp"] = attachment.extractedTimestamp?.timeIntervalSinceReferenceDate
        container["ocrText"] = attachment.ocrText
        container["thumbnailBase64"] = attachment.thumbnailBase64
    }
}

// MARK: - Preferences

public struct PreferencesRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.preferences
    public var preferences: Preferences
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(preferences: Preferences, syncState: SyncState = .dirty) {
        self.preferences = preferences
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let envelope = try decodeEnvelope(row)
        preferences = Preferences(
            createdAt: envelope.createdAt,
            updatedAt: envelope.updatedAt,
            deletedAt: envelope.deletedAt,
            notifications: Preferences.Notifications(
                reminders: row["notificationsReminders"] as Bool,
                anomalies: row["notificationsAnomalies"] as Bool,
                monthlySummary: row["notificationsMonthlySummary"] as Bool),
            eagerMediaOnWiFi: row["eagerMediaOnWiFi"] as Bool,
            defaultVehicleId: decodeOptionalUUID(row, column: "defaultVehicleId"),
            proFeedbackDiagnostics: row["proFeedbackDiagnostics"] as Bool)
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        setEnvelope(preferences, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["notificationsReminders"] = preferences.notifications.reminders
        container["notificationsAnomalies"] = preferences.notifications.anomalies
        container["notificationsMonthlySummary"] = preferences.notifications.monthlySummary
        container["eagerMediaOnWiFi"] = preferences.eagerMediaOnWiFi
        container["defaultVehicleId"] = preferences.defaultVehicleId?.uuidString
        container["proFeedbackDiagnostics"] = preferences.proFeedbackDiagnostics
    }
}

// MARK: - ExchangeRate (local cache, NOT synced - no envelope, no syncState)

public struct ExchangeRateRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.exchangeRate
    public var rate: ExchangeRate

    public init(rate: ExchangeRate) {
        self.rate = rate
    }

    public init(row: Row) throws {
        guard let base = CurrencyCode(rawValue: row["base"] as String),
              let quote = CurrencyCode(rawValue: row["quote"] as String) else {
            throw DatabaseError(message: "TankbookCore: invalid currency in exchangeRate row")
        }
        rate = ExchangeRate(
            base: base,
            quote: quote,
            date: Date(timeIntervalSinceReferenceDate: row["date"] as Double),
            rate: row["rate"] as Decimal,
            source: RateSource(rawValue: row["source"]) ?? .ecb)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["base"] = rate.base.rawValue
        container["quote"] = rate.quote.rawValue
        container["date"] = rate.date.timeIntervalSinceReferenceDate
        container["rate"] = rate.rate
        container["source"] = rate.source.rawValue
    }
}
