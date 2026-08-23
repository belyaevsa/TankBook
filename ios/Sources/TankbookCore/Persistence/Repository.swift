import Foundation
import GRDB

/// A change queued for the sync push (docs/SYNC.md, Client state & merge).
/// `entityType` matches the sync protocol's `entity_type` (the record table
/// name); `deleted` is true for tombstones. Payload encoding happens later in
/// the sync client (P4.5) against the registered JSON Schemas.
public struct PendingChange: Equatable, Sendable {
    public let entityType: String
    public let id: UUID
    public let updatedAt: Date
    public let deleted: Bool
}

/// All repository operations Phase 1 needs. Every write marks the touched row
/// `dirty` so the sync queue picks it up (docs/SYNC.md: a local write is a
/// pending change even when the row was previously synced).
///
/// Grouped into extensions by entity so each group stays small and reviewable;
/// the private helpers below are shared by all of them.
public struct TankbookRepository {
    public let database: TankbookDatabase

    public init(database: TankbookDatabase) {
        self.database = database
    }

    /// Tables whose rows belong to a vehicle and are tombstoned with it
    /// (docs/SCHEMA.md soft-delete principle + SYNC.md S5).
    private static let vehicleScopedTables = [
        TankbookSchema.fillUp, TankbookSchema.chargeSession, TankbookSchema.serviceRecord,
        TankbookSchema.expense, TankbookSchema.reminder, TankbookSchema.tireSet,
        TankbookSchema.tariff,
    ]

    /// (table, sync entity type) pairs for the dirty-queue lookup.
    private static let syncedEntities: [(table: String, entityType: String)] = [
        (TankbookSchema.vehicle, "vehicle"),
        (TankbookSchema.fillUp, "fillUp"),
        (TankbookSchema.chargeSession, "chargeSession"),
        (TankbookSchema.serviceRecord, "serviceRecord"),
        (TankbookSchema.expense, "expense"),
        (TankbookSchema.reminder, "reminder"),
        (TankbookSchema.station, "station"),
        (TankbookSchema.tariff, "tariff"),
        (TankbookSchema.tireSet, "tireSet"),
        (TankbookSchema.attachment, "attachment"),
        (TankbookSchema.preferences, "preferences"),
    ]

    /// Default tombstone grace period (docs/SCHEMA.md: "hard purge happens on a
    /// schedule" / SYNC.md: 30-day undo).
    public static let tombstoneGracePeriod: TimeInterval = 30 * 86_400
}

// MARK: - Vehicle

extension TankbookRepository {
    public func upsertVehicle(_ vehicle: Vehicle, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try VehicleRow(vehicle: vehicle, syncState: syncState).save(db)
        }
    }

    /// Tombstones the vehicle and every vehicle-scoped row at the same stamp so
    /// `restoreVehicle` can bring exactly those back.
    public func softDeleteVehicle(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            let stamp = date.timeIntervalSince1970
            try tombstone(table: TankbookSchema.vehicle, id: id, at: stamp, in: db)
            for table in Self.vehicleScopedTables {
                try tombstoneAll(forVehicle: id, in: table, at: stamp, in: db)
            }
        }
    }

    /// Restores the vehicle and the rows tombstoned together with it (they
    /// share the vehicle's `deletedAt` stamp). Individually deleted rows keep
    /// their tombstones.
    public func restoreVehicle(id: UUID) throws {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT deletedAt FROM \(TankbookSchema.vehicle) WHERE id = ?",
                                             arguments: [id.uuidString]),
                  let deletedAt = row["deletedAt"] as Double? else {
                return
            }
            let stamp = Date().timeIntervalSince1970
            try restoreRow(table: TankbookSchema.vehicle, id: id, at: stamp, in: db)
            for table in Self.vehicleScopedTables {
                try restoreAll(forVehicle: id, deletedAt: deletedAt, in: table, at: stamp, in: db)
            }
        }
    }

    public func liveVehicles() throws -> [Vehicle] {
        try database.read { db in
            try VehicleRow.filter(Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.vehicle)
        }
    }

    public func vehicle(id: UUID) throws -> Vehicle? {
        try database.read { db in
            try VehicleRow.fetchOne(db, key: id.uuidString)?.vehicle
        }
    }
}

// MARK: - FillUp

extension TankbookRepository {
    public func upsertFillUp(_ fillUp: FillUp, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try FillUpRow(fillUp: fillUp, syncState: syncState).save(db)
        }
    }

    public func softDeleteFillUp(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.fillUp, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreFillUp(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.fillUp, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveFillUps(forVehicle vehicleId: UUID) throws -> [FillUp] {
        try database.read { db in
            try fetchLive(FillUpRow.self, vehicleId: vehicleId, in: db).map(\.fillUp)
        }
    }
}

// MARK: - ChargeSession

extension TankbookRepository {
    public func upsertChargeSession(_ chargeSession: ChargeSession, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try ChargeSessionRow(chargeSession: chargeSession, syncState: syncState).save(db)
        }
    }

    public func softDeleteChargeSession(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.chargeSession, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreChargeSession(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.chargeSession, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveChargeSessions(forVehicle vehicleId: UUID) throws -> [ChargeSession] {
        try database.read { db in
            try fetchLive(ChargeSessionRow.self, vehicleId: vehicleId, in: db).map(\.chargeSession)
        }
    }
}

// MARK: - ServiceRecord

extension TankbookRepository {
    public func upsertServiceRecord(_ service: ServiceRecord, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try ServiceRecordRow(service: service, syncState: syncState).save(db)
            // Items are an ordered value list: replace wholesale.
            try db.execute(sql: "DELETE FROM \(TankbookSchema.serviceItem) WHERE serviceRecordId = ?",
                           arguments: [service.id.uuidString])
            for (position, item) in service.items.enumerated() {
                try ServiceItemRow(serviceRecordId: service.id, position: position, item: item).insert(db)
            }
        }
    }

    public func softDeleteServiceRecord(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.serviceRecord, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreServiceRecord(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.serviceRecord, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveServiceRecords(forVehicle vehicleId: UUID) throws -> [ServiceRecord] {
        try database.read { db in
            let rows = try fetchLive(ServiceRecordRow.self, vehicleId: vehicleId, in: db)
            return try attachServiceItems(rows, in: db)
        }
    }
}

// MARK: - Expense

extension TankbookRepository {
    public func upsertExpense(_ expense: Expense, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try ExpenseRow(expense: expense, syncState: syncState).save(db)
        }
    }

    public func softDeleteExpense(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.expense, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreExpense(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.expense, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveExpenses(forVehicle vehicleId: UUID) throws -> [Expense] {
        try database.read { db in
            try fetchLive(ExpenseRow.self, vehicleId: vehicleId, in: db).map(\.expense)
        }
    }

    /// The Log's union of all entry types for a vehicle, ordered by date
    /// (docs/SCHEMA.md, Entry: "The Log renders their union ordered by date").
    public func liveEntries(forVehicle vehicleId: UUID) throws -> [any Entry] {
        try database.read { db in
            let predicate = Column("vehicleId") == vehicleId.uuidString && Column("deletedAt") == nil
            let fills: [any Entry] = try FillUpRow.filter(predicate)
                .order(Column("date"), Column("createdAt")).fetchAll(db).map(\.fillUp)
            let charges: [any Entry] = try ChargeSessionRow.filter(predicate)
                .order(Column("date"), Column("createdAt")).fetchAll(db).map(\.chargeSession)
            let serviceRows = try ServiceRecordRow.filter(predicate)
                .order(Column("date"), Column("createdAt")).fetchAll(db)
            let services: [any Entry] = try attachServiceItems(serviceRows, in: db)
            let expenses: [any Entry] = try ExpenseRow.filter(predicate)
                .order(Column("date"), Column("createdAt")).fetchAll(db).map(\.expense)
            return (fills + charges + services + expenses)
                .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        }
    }
}

// MARK: - Reminder

extension TankbookRepository {
    public func upsertReminder(_ reminder: Reminder, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try ReminderRow(reminder: reminder, syncState: syncState).save(db)
        }
    }

    public func softDeleteReminder(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.reminder, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreReminder(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.reminder, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveReminders(forVehicle vehicleId: UUID) throws -> [Reminder] {
        try database.read { db in
            try fetchLiveForVehicle(ReminderRow.self, vehicleId: vehicleId, in: db).map(\.reminder)
        }
    }
}

// MARK: - Station

extension TankbookRepository {
    public func upsertStation(_ station: Station, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try StationRow(station: station, syncState: syncState).save(db)
        }
    }

    public func softDeleteStation(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.station, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreStation(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.station, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveStations() throws -> [Station] {
        try database.read { db in
            try StationRow.filter(Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.station)
        }
    }
}

// MARK: - Tariff

extension TankbookRepository {
    public func upsertTariff(_ tariff: Tariff, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try TariffRow(tariff: tariff, syncState: syncState).save(db)
        }
    }

    public func softDeleteTariff(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.tariff, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreTariff(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.tariff, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveTariffs() throws -> [Tariff] {
        try database.read { db in
            try TariffRow.filter(Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.tariff)
        }
    }
}

// MARK: - TireSet

extension TankbookRepository {
    public func upsertTireSet(_ tireSet: TireSet, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try TireSetRow(tireSet: tireSet, syncState: syncState).save(db)
        }
    }

    public func softDeleteTireSet(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.tireSet, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreTireSet(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.tireSet, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveTireSets(forVehicle vehicleId: UUID) throws -> [TireSet] {
        try database.read { db in
            try fetchLiveForVehicle(TireSetRow.self, vehicleId: vehicleId, in: db).map(\.tireSet)
        }
    }
}

// MARK: - Attachment

extension TankbookRepository {
    public func upsertAttachment(_ attachment: Attachment, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try AttachmentRow(attachment: attachment, syncState: syncState).save(db)
        }
    }

    public func softDeleteAttachment(id: UUID, at date: Date = Date()) throws {
        try database.write { db in
            try tombstone(table: TankbookSchema.attachment, id: id, at: date.timeIntervalSince1970, in: db)
        }
    }

    public func restoreAttachment(id: UUID) throws {
        try database.write { db in
            try restoreRow(table: TankbookSchema.attachment, id: id, at: Date().timeIntervalSince1970, in: db)
        }
    }

    public func liveAttachments() throws -> [Attachment] {
        try database.read { db in
            try AttachmentRow.filter(Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.attachment)
        }
    }
}

// MARK: - Preferences (single synced record, fixed id)

extension TankbookRepository {
    public func upsertPreferences(_ preferences: Preferences, syncState: SyncState = .dirty) throws {
        try database.write { db in
            try PreferencesRow(preferences: preferences, syncState: syncState).save(db)
        }
    }

    public func livePreferences() throws -> Preferences? {
        try database.read { db in
            try PreferencesRow.fetchOne(db)?.preferences
        }
    }
}

// MARK: - ExchangeRate (local cache, never synced)

extension TankbookRepository {
    public func upsertExchangeRate(_ rate: ExchangeRate) throws {
        try database.write { db in
            try ExchangeRateRow(rate: rate).save(db)
        }
    }

    public func exchangeRate(base: CurrencyCode, quote: CurrencyCode, on date: Date) throws -> ExchangeRate? {
        try database.read { db in
            try ExchangeRateRow
                .filter(Column("base") == base.rawValue
                    && Column("quote") == quote.rawValue
                    && Column("date") == date.timeIntervalSince1970)
                .fetchOne(db)?
                .rate
        }
    }
}

// MARK: - DuplicateResolution (S2, device-local)

extension TankbookRepository {
    /// Records a user's "keep both" decision for an S2 pair (docs/SYNC.md S2):
    /// from then on BOTH entries count - the heuristic is suppressed for this
    /// pair. Device-local until sync lands (P4).
    public func upsertDuplicateResolution(_ resolution: DuplicateResolution) throws {
        try database.write { db in
            try DuplicateResolutionRow(resolution: resolution).save(db)
        }
    }

    public func liveDuplicateResolutions() throws -> [DuplicateResolution] {
        try database.read { db in
            try DuplicateResolutionRow.filter(Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.resolution)
        }
    }

    /// The order-independent keys of every recorded resolution, as the pure
    /// heuristic expects them (docs/SYNC.md S2 "Keep both": the derived
    /// detector skips a pair whose key is here).
    public func resolvedDuplicateKeys() throws -> Set<DuplicateDetector.PairKey> {
        let resolutions = try liveDuplicateResolutions()
        return Set(resolutions.compactMap { resolution in
            let low: UUID
            let high: UUID
            if resolution.countedEntryID.uuidString < resolution.excludedEntryID.uuidString {
                low = resolution.countedEntryID
                high = resolution.excludedEntryID
            } else {
                low = resolution.excludedEntryID
                high = resolution.countedEntryID
            }
            return DuplicateDetector.PairKey(low: low, high: high)
        })
    }
}

// MARK: - Sync queue + purge

extension TankbookRepository {
    /// Number of rows in `table`, tombstones included. Used by tests and the
    /// diagnostics export to observe physical state.
    public func rowCount(in table: String) throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }

    /// Permanently removes the vehicle row; child rows cascade via the FK
    /// (`ON DELETE CASCADE`). This is the physical-purge path behind the
    /// scheduled tombstone purge (docs/SYNC.md S5 "hard delete demands typed
    /// confirmation"). Normal deletes go through `softDeleteVehicle`.
    public func hardDeleteVehicle(id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM \(TankbookSchema.vehicle) WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    /// All dirty rows across every synced table, oldest first - the input to
    /// the push half of the sync cycle (docs/SYNC.md, Protocol).
    public func fetchDirtyRows() throws -> [PendingChange] {
        try database.read { db in
            var changes: [PendingChange] = []
            for entity in Self.syncedEntities {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, updatedAt, deletedAt FROM \(entity.table)
                    WHERE syncState = 'dirty'
                    ORDER BY updatedAt
                    """)
                for row in rows {
                    guard let id = UUID(uuidString: row["id"] as String) else { continue }
                    changes.append(PendingChange(
                        entityType: entity.entityType,
                        id: id,
                        updatedAt: Date(timeIntervalSince1970: row["updatedAt"] as Double),
                        deleted: (row["deletedAt"] as Double?) != nil))
                }
            }
            return changes.sorted { $0.updatedAt < $1.updatedAt }
        }
    }

    /// Hard-deletes tombstoned rows older than `cutoff` (default: the 30-day
    /// undo window). Entry tombstones are purged before vehicle tombstones,
    /// and a vehicle tombstone is kept while any of its rows are still live, so
    /// the FK cascade can never delete a live row (nothing is lost silently).
    public func purgeTombstones(
        olderThan cutoff: Date = Date().addingTimeInterval(-Self.tombstoneGracePeriod)
    ) throws {
        try database.write { db in
            let cutoff = cutoff.timeIntervalSince1970
            let entryTables = TankbookSchema.entryTables
            for table in entryTables {
                try db.execute(sql: """
                    DELETE FROM \(table)
                    WHERE deletedAt IS NOT NULL AND deletedAt < ?
                    """, arguments: [cutoff])
            }
            for table in TankbookSchema.syncedTables where !entryTables.contains(table) && table != TankbookSchema.vehicle {
                try db.execute(sql: """
                    DELETE FROM \(table)
                    WHERE deletedAt IS NOT NULL AND deletedAt < ?
                    """, arguments: [cutoff])
            }
            let liveChecks = Self.vehicleScopedTables.map { table in
                "(EXISTS (SELECT 1 FROM \(table) WHERE vehicleId = vehicle.id AND deletedAt IS NULL))"
            }
            try db.execute(sql: """
                DELETE FROM vehicle
                WHERE deletedAt IS NOT NULL AND deletedAt < ?
                  AND NOT (\(liveChecks.joined(separator: " OR ")))
                """, arguments: [cutoff])
        }
    }
}

// MARK: - Recently deleted (P1.7)

extension TankbookRepository {
    /// All tombstoned entries across the entry tables, newest deletion first -
    /// the Recently deleted screen's data (hard rule 8: nothing lost silently;
    /// every tombstone lives here for the 30-day window). Each row knows what
    /// it was (the entry is intact), when it was deleted and how long it has
    /// left. `deletedOnDevice` is nil - the real device attribution arrives
    /// with sync (P4); the app target fakes it for fixtures.
    public func deletedEntries() throws -> [DeletedEntry] {
        try database.read { db in
            var result: [DeletedEntry] = []
            let predicate = Column("deletedAt") != nil

            let fills: [DeletedEntry] = try FillUpRow
                .filter(predicate).fetchAll(db)
                .compactMap { $0.fillUp.deletedAt != nil ? DeletedEntry(entry: $0.fillUp) : nil }
            result.append(contentsOf: fills)

            let charges: [DeletedEntry] = try ChargeSessionRow
                .filter(predicate).fetchAll(db)
                .compactMap { $0.chargeSession.deletedAt != nil ? DeletedEntry(entry: $0.chargeSession) : nil }
            result.append(contentsOf: charges)

            let serviceRows = try ServiceRecordRow.filter(predicate).fetchAll(db)
            let services: [DeletedEntry] = serviceRows
                .compactMap { $0.service.deletedAt != nil ? DeletedEntry(entry: $0.service) : nil }
            result.append(contentsOf: services)

            let expenses: [DeletedEntry] = try ExpenseRow
                .filter(predicate).fetchAll(db)
                .compactMap { $0.expense.deletedAt != nil ? DeletedEntry(entry: $0.expense) : nil }
            result.append(contentsOf: expenses)

            return result.sorted { ($0.deletedAt, $0.entry.date) > ($1.deletedAt, $1.entry.date) }
        }
    }

    /// Restores any tombstoned entry - the screen's Restore button (hard rule
    /// 8: restoring clears the tombstone and the entry re-enters the Log and
    /// the statistics, because stats are derived and the next recompute sees
    /// the live row again - docs/SCHEMA.md, Recalculation on edit). Returns
    /// true when a tombstone was found and restored.
    @discardableResult
    public func restoreEntry(id: UUID) throws -> Bool {
        try database.write { db in
            let stamp = Date().timeIntervalSince1970
            for table in TankbookSchema.entryTables {
                try db.execute(sql: """
                    UPDATE \(table)
                    SET deletedAt = NULL, updatedAt = ?, syncState = 'dirty', syncScn = NULL
                    WHERE id = ? AND deletedAt IS NOT NULL
                    """, arguments: [stamp, id.uuidString])
                if db.changesCount > 0 { return true }
            }
            return false
        }
    }

    /// Permanently removes EVERY tombstone regardless of age - the Recently
    /// deleted screen's destructive "Delete all now" (system-confirmed, the one
    /// place red lives, hard rule 5). This is the same purge path as the
    /// scheduled one (same safety rule: a vehicle tombstone is kept while any
    /// of its rows are still live), just with no grace period. Idempotent.
    public func purgeAllTombstones() throws {
        try purgeTombstones(olderThan: Date())
    }
}

// MARK: - Helpers

extension TankbookRepository {
    private func fetchLive<Record: FetchableRecord & TableRecord>(
        _ type: Record.Type, vehicleId: UUID, in db: Database
    ) throws -> [Record] {
        try Record
            .filter(Column("vehicleId") == vehicleId.uuidString && Column("deletedAt") == nil)
            .order(Column("date"), Column("createdAt"))
            .fetchAll(db)
    }

    private func fetchLiveForVehicle<Record: FetchableRecord & TableRecord>(
        _ type: Record.Type, vehicleId: UUID, in db: Database
    ) throws -> [Record] {
        try Record
            .filter(Column("vehicleId") == vehicleId.uuidString && Column("deletedAt") == nil)
            .order(Column("createdAt"))
            .fetchAll(db)
    }

    private func attachServiceItems(_ rows: [ServiceRecordRow], in db: Database) throws -> [ServiceRecord] {
        let ids = rows.map { $0.service.id.uuidString }
        guard !ids.isEmpty else { return rows.map(\.service) }
        let itemRows = try ServiceItemRow
            .filter(ids.contains(Column("serviceRecordId")))
            .order(Column("serviceRecordId"), Column("position"))
            .fetchAll(db)
        var itemsByRecord: [UUID: [ServiceItem]] = [:]
        for itemRow in itemRows {
            itemsByRecord[itemRow.serviceRecordId, default: []].append(itemRow.item)
        }
        var services = rows.map(\.service)
        for index in services.indices {
            services[index].items = itemsByRecord[services[index].id] ?? []
        }
        return services
    }

    private func tombstone(table: String, id: UUID, at stamp: TimeInterval, in db: Database) throws {
        try db.execute(sql: """
            UPDATE \(table)
            SET deletedAt = ?, updatedAt = ?, syncState = 'dirty', syncScn = NULL
            WHERE id = ? AND deletedAt IS NULL
            """, arguments: [stamp, stamp, id.uuidString])
    }

    private func restoreRow(table: String, id: UUID, at stamp: TimeInterval, in db: Database) throws {
        try db.execute(sql: """
            UPDATE \(table)
            SET deletedAt = NULL, updatedAt = ?, syncState = 'dirty', syncScn = NULL
            WHERE id = ? AND deletedAt IS NOT NULL
            """, arguments: [stamp, id.uuidString])
    }

    private func tombstoneAll(forVehicle vehicleId: UUID, in table: String, at stamp: TimeInterval, in db: Database) throws {
        try db.execute(sql: """
            UPDATE \(table)
            SET deletedAt = ?, updatedAt = ?, syncState = 'dirty', syncScn = NULL
            WHERE vehicleId = ? AND deletedAt IS NULL
            """, arguments: [stamp, stamp, vehicleId.uuidString])
    }

    private func restoreAll(forVehicle vehicleId: UUID, deletedAt: TimeInterval, in table: String, at stamp: TimeInterval, in db: Database) throws {
        try db.execute(sql: """
            UPDATE \(table)
            SET deletedAt = NULL, updatedAt = ?, syncState = 'dirty', syncScn = NULL
            WHERE vehicleId = ? AND deletedAt = ?
            """, arguments: [stamp, vehicleId.uuidString, deletedAt])
    }
}
