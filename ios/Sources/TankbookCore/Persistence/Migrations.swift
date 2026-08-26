import Foundation
import GRDB

/// Canonical table names. `TankbookCore` is the only writer of these tables;
/// the names are shared by migrations, record types and the repository so they
/// can never drift apart. Table/column naming follows docs/SCHEMA.md verbatim
/// (camelCase in SQLite is fine - it is not a PostgreSQL schema).
public enum TankbookSchema {
    public static let vehicle = "vehicle"
    public static let fillUp = "fillUp"
    public static let chargeSession = "chargeSession"
    public static let serviceRecord = "serviceRecord"
    public static let serviceItem = "serviceItem"
    public static let expense = "expense"
    public static let reminder = "reminder"
    public static let station = "station"
    public static let tariff = "tariff"
    public static let tireSet = "tireSet"
    public static let attachment = "attachment"
    public static let preferences = "preferences"
    public static let exchangeRate = "exchangeRate"
    /// Device-local record of S2 duplicate resolutions ("keep both") - NOT in
    /// `syncedTables`: it is derived-state bookkeeping, like the sync cursor.
    public static let duplicateResolution = "duplicateResolution"
    /// Device-local undo log of versions a sync merge overwrote (docs/SYNC.md
    /// S1/S4: "the losing version is kept in a local 30-day undo log"). NOT in
    /// `syncedTables` - it is bookkeeping, like the sync cursor.
    public static let syncOverwrite = "syncOverwrite"

    /// Every synced entity table (has the envelope + syncState bookkeeping).
    /// The reference data (exchangeRate) is deliberately NOT here.
    public static let syncedTables: [String] = [
        vehicle, fillUp, chargeSession, serviceRecord, expense,
        reminder, station, tariff, tireSet, attachment, preferences,
    ]

    /// Entry tables: carry the EntryCommon envelope plus a vehicle FK.
    public static let entryTables: [String] = [
        fillUp, chargeSession, serviceRecord, expense,
    ]

    /// Money columns are flattened per docs/SCHEMA.md (Money). Unprefixed on
    /// entry tables (`amount`, `currency`, ...); prefixed and capitalized on
    /// the serviceItem child table (`costAmount`, `costCurrency`, ...).
    public static func moneyColumn(_ prefix: String, _ base: String) -> String {
        prefix.isEmpty ? base : prefix + base.prefix(1).uppercased() + base.dropFirst()
    }
}

/// Storage conventions (documented once, here):
///
/// - **Decimal is stored as TEXT.** GRDB's built-in `Decimal` conformance
///   encodes `NSDecimalNumber.description` (en_US_POSIX) and decodes back with
///   `Decimal(string:)` - both exact, so values like `1.679` or `0.1 + 0.2`
///   round-trip with no floating-point drift. No `Double` conversion anywhere
///   on the money path. (docs/SCHEMA.md: "Money is always a pair", rate
///   snapshots are immutable.)
/// - **Dates are stored as REAL** (`timeIntervalSinceReferenceDate`). GRDB's
///   default `Date` encoding is a millisecond-truncated TEXT, which would
///   corrupt sub-millisecond round-trips; a Double of the reference-date
///   interval round-trips exactly because `Date` is itself that Double
///   internally. `timeIntervalSince1970` was the original format, but adding
///   the 978307200 s epoch offset shifts the fractional bits out of the Double
///   mantissa, so a written date read straight back drifted by one ulp
///   (~1.2e-7 s). The `v3` migration converts every date column in place.
/// - **`syncState` / `syncScn`** on every synced table implement the local
///   sync bookkeeping from docs/SYNC.md ("Client state & merge").
public enum TankbookMigrations {
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createVehicle(db)
            for entryTable in TankbookSchema.entryTables {
                try createEntryTable(named: entryTable, db: db)
            }
            try createServiceItem(db)
            try createReminder(db)
            try createStation(db)
            try createTariff(db)
            try createTireSet(db)
            try createAttachment(db)
            try createPreferences(db)
            try createExchangeRate(db)
            try createDuplicateResolution(db)
            try createIndexes(db)
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: TankbookSchema.fillUp) { table in
                table.add(column: "fiscalIdentity", .text)   // JSON FiscalDocumentIdentity?
            }
        }
        migrator.registerMigration("v3") { db in
            try convertDateColumnsToReferenceDate(db)
        }
        migrator.registerMigration("v4") { db in
            try createSyncOverwrite(db)
        }
        return migrator
    }

    // MARK: - Date columns (P4.11)

    /// Seconds between the 2001 reference date and the 1970 Unix epoch:
    /// `timeIntervalSince1970 == timeIntervalSinceReferenceDate + epochOffset`.
    private static let epochOffset: Double = 978_307_200

    /// Every column that stores a `Date` as a REAL Double, as (table, column).
    /// This is the complete inventory - a column missed here is a silently
    /// half-migrated database. Envelope columns live on every table that has an
    /// envelope; the rest are the per-entity date fields plus the flattened
    /// Money `rateDate` and the local `exchangeRate.date` cache.
    private static let dateColumns: [(table: String, column: String)] = {
        let envelopeTables = TankbookSchema.syncedTables + [TankbookSchema.duplicateResolution]
        var columns: [(String, String)] = []
        for table in envelopeTables {
            columns.append((table, "createdAt"))
            columns.append((table, "updatedAt"))
            columns.append((table, "deletedAt"))
        }
        for table in TankbookSchema.entryTables {
            columns.append((table, "date"))
            columns.append((table, "rateDate"))
        }
        columns.append((TankbookSchema.serviceItem, "costRateDate"))
        columns.append((TankbookSchema.vehicle, "archivedAt"))
        columns.append((TankbookSchema.reminder, "dueDate"))
        columns.append((TankbookSchema.station, "lastUsedAt"))
        columns.append((TankbookSchema.tariff, "validFrom"))
        columns.append((TankbookSchema.attachment, "extractedTimestamp"))
        columns.append((TankbookSchema.exchangeRate, "date"))
        return columns
    }()

    /// P4.11: rewrites every date column from `timeIntervalSince1970` seconds to
    /// `timeIntervalSinceReferenceDate` seconds (subtracting the epoch offset).
    /// Applied once by the `v3` migration; a fresh database has no rows so the
    /// updates are no-ops.
    private static func convertDateColumnsToReferenceDate(_ db: Database) throws {
        for (table, column) in dateColumns {
            try db.execute(
                sql: "UPDATE \(table) SET \(column) = \(column) - ? WHERE \(column) IS NOT NULL",
                arguments: [epochOffset])
        }
    }

    // MARK: - Tables

    private static func createVehicle(_ db: Database) throws {
        try db.create(table: TankbookSchema.vehicle) { table in
            envelopeColumns(on: table)
            table.column("name", .text).notNull()
            table.column("make", .text)
            table.column("model", .text)
            table.column("year", .integer)
            table.column("plate", .text)
            table.column("powertrain", .text).notNull()
            table.column("fuelKinds", .text).notNull()   // JSON [FuelKind]
            table.column("tankCapacityL", .double)
            table.column("batteryCapacityKWh", .double)
            table.column("homeCurrency", .text).notNull()
            table.column("distanceUnit", .text).notNull()
            table.column("volumeUnit", .text).notNull()
            table.column("consumptionUnit", .text).notNull()
            table.column("energyUnit", .text).notNull()
            table.column("photo", .text)
            table.column("archived", .integer).notNull().defaults(to: false)
            // Added to v1 rather than as a v2 migration: no build has ever
            // shipped, so no database exists in the field to migrate.
            table.column("archivedAt", .double)
            table.column("paceLimitKmPerDay", .double).notNull().defaults(to: 1500)
            // Added to v1 rather than as a v2 migration: no build has ever
            // shipped, so no database exists in the field to migrate.
            table.column("initialOdometer", .integer)
        }
    }

    private static func createEntryTable(named tableName: String, db: Database) throws {
        try db.create(table: tableName) { table in
            envelopeColumns(on: table)
            entryCommonColumns(on: table)
            switch tableName {
            case TankbookSchema.fillUp: fillUpColumns(on: table)
            case TankbookSchema.chargeSession: chargeSessionColumns(on: table)
            case TankbookSchema.serviceRecord: serviceRecordColumns(on: table)
            case TankbookSchema.expense: expenseColumns(on: table)
            default: break
            }
        }
    }

    private static func entryCommonColumns(on table: TableDefinition) {
        // EntryCommon (docs/SCHEMA.md, Entry):
        table.column("vehicleId", .text).notNull()
            .references(TankbookSchema.vehicle, onDelete: .cascade)
        table.column("date", .double).notNull()
        table.column("odometer", .integer)
        // Money, flattened (docs/SCHEMA.md, Money):
        moneyColumns(prefix: "", on: table)
        table.column("note", .text)
        table.column("provenance", .text).notNull()     // JSON Provenance
        table.column("conflict", .text).notNull()       // JSON ConflictState
        table.column("purchaseGroupId", .text)
        table.column("attachments", .text).notNull().defaults(to: "[]")   // JSON [AttachmentID]
    }

    private static func fillUpColumns(on table: TableDefinition) {
        table.column("volumeL", .double).notNull()
        table.column("unitPrice", .text)                // Decimal
        table.column("fuelKind", .text).notNull()
        table.column("fuelGrade", .text)
        table.column("isFull", .integer).notNull().defaults(to: false)
        table.column("tankLevelAfterPct", .double)
        table.column("stationId", .text)
        table.column("crossCheck", .text).notNull().defaults(to: "\"verified\"")   // JSON CrossCheckState
        table.column("extraction", .text)               // JSON ExtractionMeta?
    }

    private static func chargeSessionColumns(on table: TableDefinition) {
        table.column("energyKWh", .double).notNull()
        table.column("unitPrice", .text)                // Decimal
        table.column("chargeType", .text).notNull()
        table.column("provider", .text)
        table.column("tariffId", .text)
        table.column("durationMin", .integer)
        table.column("socStartPct", .double)
        table.column("socEndPct", .double)
        table.column("extraction", .text)               // JSON ExtractionMeta?
    }

    private static func serviceRecordColumns(on table: TableDefinition) {
        table.column("vendor", .text)
        table.column("usedParts", .text).notNull().defaults(to: "[]")    // JSON [UUID]
        table.column("tireSetId", .text)
        table.column("proposedReminderId", .text)
    }

    private static func expenseColumns(on table: TableDefinition) {
        table.column("category", .text).notNull()       // JSON ExpenseCategory
        table.column("title", .text).notNull()
        table.column("recurrence", .text)               // JSON RecurrenceRule?
        table.column("installedInServiceId", .text)
    }

    private static func createServiceItem(_ db: Database) throws {
        // Normalized child of serviceRecord: SCHEMA.md models `items:
        // [ServiceItem]` as an ordered value list, so the child rows carry a
        // position and reconstruct the array in that order.
        try db.create(table: TankbookSchema.serviceItem) { table in
            table.column("serviceRecordId", .text).notNull()
                .references(TankbookSchema.serviceRecord, onDelete: .cascade)
            table.column("position", .integer).notNull()
            table.column("title", .text).notNull()
            table.column("category", .text).notNull()       // JSON ServiceCategory
            moneyColumns(prefix: "cost", on: table)         // ServiceItem.cost (Money?)
            table.column("partNumber", .text)
            table.column("lifetime", .text)                 // JSON ServiceItem.Lifetime?; NULL = no lifetime
            table.primaryKey(["serviceRecordId", "position"])        }
    }

    private static func createReminder(_ db: Database) throws {
        try db.create(table: TankbookSchema.reminder) { table in
            envelopeColumns(on: table)
            table.column("vehicleId", .text).notNull()
                .references(TankbookSchema.vehicle, onDelete: .cascade)
            table.column("title", .text).notNull()
            table.column("category", .text).notNull()       // JSON ReminderCategory
            table.column("dueDate", .double)
            table.column("dueOdometer", .integer)
            table.column("recurrence", .text)               // JSON Reminder.Recurrence?
            table.column("sourceEntryId", .text)
            table.column("status", .text).notNull()         // JSON ReminderStatus
        }
    }

    private static func createStation(_ db: Database) throws {
        try db.create(table: TankbookSchema.station) { table in
            envelopeColumns(on: table)
            table.column("name", .text).notNull()
            table.column("brand", .text)
            table.column("locationLat", .double)            // GeoCoordinate?
            table.column("locationLng", .double)
            table.column("favorite", .integer).notNull().defaults(to: false)
            table.column("defaults", .text).notNull().defaults(to: "{}")   // JSON Station.Defaults
            table.column("lastUsedAt", .double)
        }
    }

    private static func createTariff(_ db: Database) throws {
        try db.create(table: TankbookSchema.tariff) { table in
            envelopeColumns(on: table)
            table.column("vehicleId", .text)                // nil = household-wide; not a hard FK
            table.column("name", .text).notNull()
            table.column("pricePerKWh", .text).notNull()    // Decimal
            table.column("currency", .text).notNull()
            table.column("validFrom", .double).notNull()
        }
    }

    private static func createTireSet(_ db: Database) throws {
        try db.create(table: TankbookSchema.tireSet) { table in
            envelopeColumns(on: table)
            table.column("vehicleId", .text).notNull()
                .references(TankbookSchema.vehicle, onDelete: .cascade)
            table.column("name", .text).notNull()
            table.column("purchaseExpenseId", .text)
        }
    }

    private static func createAttachment(_ db: Database) throws {
        try db.create(table: TankbookSchema.attachment) { table in
            envelopeColumns(on: table)
            table.column("kind", .text).notNull()           // AttachmentKind rawValue
            table.column("fileSha256", .text).notNull()     // LocalFileRef
            table.column("fileRelativePath", .text).notNull()
            table.column("extractedTimestamp", .double)
            table.column("ocrText", .text)
        }
    }

    private static func createPreferences(_ db: Database) throws {
        try db.create(table: TankbookSchema.preferences) { table in
            envelopeColumns(on: table)
            table.column("notificationsReminders", .integer).notNull().defaults(to: true)
            table.column("notificationsAnomalies", .integer).notNull().defaults(to: true)
            table.column("notificationsMonthlySummary", .integer).notNull().defaults(to: false)
            table.column("eagerMediaOnWiFi", .integer).notNull().defaults(to: false)
            table.column("defaultVehicleId", .text)
            table.column("proFeedbackDiagnostics", .integer).notNull().defaults(to: false)
        }
    }

    private static func createExchangeRate(_ db: Database) throws {
        // Local rate cache, deliberately NOT synced (docs/SCHEMA.md,
        // ExchangeRate): no envelope, no id, no syncState. Keyed by the same
        // (date, base, quote) triple as the backend reference table.
        try db.create(table: TankbookSchema.exchangeRate) { table in
            table.column("base", .text).notNull()
            table.column("quote", .text).notNull()
            table.column("date", .double).notNull()
            table.column("rate", .text).notNull()           // Decimal
            table.column("source", .text).notNull()
            table.primaryKey(["base", "quote", "date"])
        }
    }

    private static func createDuplicateResolution(_ db: Database) throws {
        // A user's "keep both" on an S2 pair (docs/SYNC.md S2). Device-local
        // like the sync cursor - deliberately NO syncState/syncScn columns.
        try db.create(table: TankbookSchema.duplicateResolution) { table in
            envelopeColumns(on: table)
            table.column("countedEntryID", .text).notNull()
            table.column("excludedEntryID", .text).notNull()
            table.column("resolution", .text).notNull()     // DuplicateResolution.Resolution
        }
    }

    private static func createSyncOverwrite(_ db: Database) throws {
        // The local 30-day undo log of versions a sync merge overwrote
        // (docs/SYNC.md S1/S4). Device-local like the sync cursor - deliberately
        // NO syncState/syncScn columns, and not in `syncedTables`.
        try db.create(table: TankbookSchema.syncOverwrite) { table in
            table.column("id", .text).primaryKey()
            table.column("recordId", .text).notNull()
            table.column("entityType", .text).notNull()
            table.column("losingPayload", .text).notNull()     // canonical JSON of the losing payload
            table.column("losingUpdatedAt", .double).notNull()
            table.column("replacedAt", .double).notNull()
        }
        try db.create(index: "idx_syncOverwrite_record", on: TankbookSchema.syncOverwrite,
                      columns: ["recordId", "replacedAt"])
    }

    // MARK: - Shared column groups

    private static func envelopeColumns(on table: TableDefinition) {
        table.column("id", .text).primaryKey()              // UUID as TEXT (SCHEMA.md)
        table.column("createdAt", .double).notNull()
        table.column("updatedAt", .double).notNull()
        table.column("deletedAt", .double)                  // tombstone; nil = live
        table.column("syncState", .text).notNull().defaults(to: "dirty")
        table.column("syncScn", .integer)
    }

    /// The flattened Money pair (docs/SCHEMA.md, Money): original amount and
    /// currency, the home-currency conversion with its rate snapshot, and the
    /// rate source. `homeAmount`/`rate`/`rateDate` are all-or-nothing for a
    /// cross-currency snapshot; same-currency money is snapshotted at rate 1
    /// with a nil `rateDate`.
    private static func moneyColumns(prefix: String, on table: TableDefinition) {
        for base in ["amount", "currency", "homeAmount", "homeCurrency", "rate"] {
            table.column(TankbookSchema.moneyColumn(prefix, base), .text)
        }
        table.column(TankbookSchema.moneyColumn(prefix, "rateDate"), .double)
        table.column(TankbookSchema.moneyColumn(prefix, "rateSource"), .text)
    }

    // MARK: - Indexes (the queries Phase 1 actually runs)

    private static func createIndexes(_ db: Database) throws {
        for entryTable in TankbookSchema.entryTables {
            // Log / timeline queries order entries by date within a vehicle:
            try db.create(index: "idx_\(entryTable)_vehicle_date",
                          on: entryTable, columns: ["vehicleId", "date"])
            // Odometer lookups ("last known value" pre-fill) and validation:
            try db.create(index: "idx_\(entryTable)_vehicle_odometer",
                          on: entryTable, columns: ["vehicleId", "odometer"])
            // Tombstone filtering: live rows only, per vehicle, date-ordered.
            try db.create(index: "idx_\(entryTable)_live",
                          on: entryTable, columns: ["vehicleId", "date"],
                          condition: Column("deletedAt") == nil)
            // Dirty-row lookup for the sync queue:
            try db.create(index: "idx_\(entryTable)_sync",
                          on: entryTable, columns: ["syncState", "updatedAt"])
        }
        for table in TankbookSchema.syncedTables where !TankbookSchema.entryTables.contains(table) {
            try db.create(index: "idx_\(table)_sync",
                          on: table, columns: ["syncState", "updatedAt"])
        }
        // Rolling "keep ~2 years" purge of the local rate cache:
        try db.create(index: "idx_exchangeRate_date", on: TankbookSchema.exchangeRate, columns: ["date"])
    }
}
