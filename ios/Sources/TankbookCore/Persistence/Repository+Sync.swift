import Foundation
import GRDB

// The sync client's persistence surface (P4.5): reads a local row back as a
// `SyncRecord`, applies a remote record as synced, drives the dirty/pushing/
// synced state machine, records versions a merge overwrote, and re-runs the
// domain timeline validation after a merge batch (docs/SYNC.md, S1-S9).

/// A local row plus the sync bookkeeping the push half needs.
public struct LocalSyncRecord: Equatable, Sendable {
    public let record: SyncRecord
    /// The server SCN this row last had (0 = never accepted). The push's base.
    public let baseScn: Int64
    public let syncState: SyncState

    public init(record: SyncRecord, baseScn: Int64, syncState: SyncState) {
        self.record = record
        self.baseScn = baseScn
        self.syncState = syncState
    }
}

/// A version a sync merge overwrote (docs/SYNC.md S1/S4: the local 30-day undo
/// log). Device-local bookkeeping, like the sync cursor - never synced.
public struct SyncOverwrite: Equatable, Sendable {
    public let id: UUID
    public let recordId: UUID
    public let entityType: String
    public let losingPayload: JSONValue
    public let losingUpdatedAt: Date
    public let replacedAt: Date
}

/// The sync bookkeeping every synced row type already carries. Conforming it
/// here lets the entity dispatch below stay a flat switch - one branch per
/// case - instead of an 11-way `guard let` sprawl.
protocol SyncRowState {
    var syncScn: Int64? { get }
    var syncState: SyncState { get }
}

extension VehicleRow: SyncRowState {}
extension FillUpRow: SyncRowState {}
extension ChargeSessionRow: SyncRowState {}
extension ServiceRecordRow: SyncRowState {}
extension ExpenseRow: SyncRowState {}
extension ReminderRow: SyncRowState {}
extension StationRow: SyncRowState {}
extension TariffRow: SyncRowState {}
extension TireSetRow: SyncRowState {}
extension AttachmentRow: SyncRowState {}
extension PreferencesRow: SyncRowState {}

// MARK: - Local read + state machine

extension TankbookRepository {
    /// Maps an entityType to its table name, or nil for a type this build does
    /// not know (forward compatibility: unknown types are stored opaquely - but
    /// the sync client only pushes/pulls the types it knows).
    func table(for entityType: String) -> String? {
        switch entityType {
        case Vehicle.entityType: TankbookSchema.vehicle
        case FillUp.entityType: TankbookSchema.fillUp
        case ChargeSession.entityType: TankbookSchema.chargeSession
        case ServiceRecord.entityType: TankbookSchema.serviceRecord
        case Expense.entityType: TankbookSchema.expense
        case Reminder.entityType: TankbookSchema.reminder
        case Station.entityType: TankbookSchema.station
        case Tariff.entityType: TankbookSchema.tariff
        case TireSet.entityType: TankbookSchema.tireSet
        case Attachment.entityType: TankbookSchema.attachment
        case Preferences.entityType: TankbookSchema.preferences
        default: nil
        }
    }

    /// Reads a local row as a `SyncRecord` plus its base SCN and state.
    public func localSyncRecord(id: UUID, entityType: String) throws -> LocalSyncRecord? {
        try database.read { db in
            switch entityType {
            case Vehicle.entityType:
                return fetchLocal(VehicleRow.self, id: id, entityType: entityType, in: db) { $0.vehicle }
            case FillUp.entityType:
                return fetchLocal(FillUpRow.self, id: id, entityType: entityType, in: db) { $0.fillUp }
            case ChargeSession.entityType:
                return fetchLocal(ChargeSessionRow.self, id: id, entityType: entityType, in: db) { $0.chargeSession }
            case ServiceRecord.entityType:
                return fetchServiceRecord(id: id, entityType: entityType, in: db)
            case Expense.entityType:
                return fetchLocal(ExpenseRow.self, id: id, entityType: entityType, in: db) { $0.expense }
            case Reminder.entityType:
                return fetchLocal(ReminderRow.self, id: id, entityType: entityType, in: db) { $0.reminder }
            case Station.entityType:
                return fetchLocal(StationRow.self, id: id, entityType: entityType, in: db) { $0.station }
            case Tariff.entityType:
                return fetchLocal(TariffRow.self, id: id, entityType: entityType, in: db) { $0.tariff }
            case TireSet.entityType:
                return fetchLocal(TireSetRow.self, id: id, entityType: entityType, in: db) { $0.tireSet }
            case Attachment.entityType:
                return fetchLocal(AttachmentRow.self, id: id, entityType: entityType, in: db) { $0.attachment }
            case Preferences.entityType:
                return fetchLocal(PreferencesRow.self, id: id, entityType: entityType, in: db) { $0.preferences }
            default:
                return nil
            }
        }
    }

    private func fetchLocal<R: FetchableRecord & TableRecord & SyncRowState, E: SyncedEntity>(
        _ type: R.Type, id: UUID, entityType: String, in db: Database, entity: (R) -> E
    ) -> LocalSyncRecord? {
        guard let row = try? R.fetchOne(db, key: id.uuidString) else { return nil }
        let value = entity(row)
        return makeLocal(value, entityType: entityType, id: id, updatedAt: value.updatedAt,
                         deletedAt: value.deletedAt, scn: row.syncScn, state: row.syncState)
    }

    private func fetchServiceRecord(id: UUID, entityType: String, in db: Database) -> LocalSyncRecord? {
        guard let row = try? ServiceRecordRow.fetchOne(db, key: id.uuidString) else { return nil }
        var service = row.service
        service.items = (try? ServiceItemRow.filter(Column("serviceRecordId") == id.uuidString)
            .order(Column("position")).fetchAll(db).map(\.item)) ?? []
        return makeLocal(service, entityType: entityType, id: id, updatedAt: service.updatedAt,
                         deletedAt: service.deletedAt, scn: row.syncScn, state: row.syncState)
    }

    private func makeLocal<E: SyncedEntity>(_ entity: E, entityType: String, id: UUID,
                                            updatedAt: Date, deletedAt: Date?, scn: Int64?,
                                            state: SyncState) -> LocalSyncRecord? {
        guard let payload = try? PayloadCodec.encode(entity).payload else { return nil }
        let record = SyncRecord(
            id: id,
            entityType: entityType,
            schemaVersion: PayloadCodec.currentSchemaVersion,
            payload: payload,
            clientUpdatedAt: updatedAt,
            deleted: deletedAt != nil
        )
        return LocalSyncRecord(record: record, baseScn: scn ?? 0, syncState: state)
    }

    /// Marks rows `pushing` (in flight), preserving their base SCN.
    public func markPushing(ids: [(id: UUID, entityType: String)]) throws {
        try database.write { db in
            for item in ids {
                guard let table = table(for: item.entityType) else { continue }
                try db.execute(sql: "UPDATE \(table) SET syncState = 'pushing' WHERE id = ?",
                               arguments: [item.id.uuidString])
            }
        }
    }

    /// Marks a row `synced` at `scn` (the server accepted it).
    public func markSynced(id: UUID, entityType: String, scn: Int64) throws {
        try database.write { db in
            guard let table = table(for: entityType) else { return }
            try db.execute(sql: "UPDATE \(table) SET syncState = 'synced', syncScn = ? WHERE id = ?",
                           arguments: [scn, id.uuidString])
        }
    }

    /// Returns a row to `.dirty` after a failed push (docs/SyncState.swift).
    public func markDirty(id: UUID, entityType: String) throws {
        try database.write { db in
            guard let table = table(for: entityType) else { return }
            try db.execute(sql: "UPDATE \(table) SET syncState = 'dirty' WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }
}

// MARK: - Apply a record

extension TankbookRepository {
    /// Writes a record locally at the given sync state. Returns the vehicle ids
    /// the record touches, for domain re-validation. A `.synced` write carries
    /// its SCN; a `.dirty` write keeps the row's base SCN (a merged `Vehicle`
    /// is a new local write that must still push - docs/SYNC.md S9).
    public func applyRecord(_ record: SyncRecord, syncState: SyncState) throws -> Set<UUID> {
        switch record.entityType {
        case Vehicle.entityType:
            return try apply(record, syncState: syncState, as: Vehicle.self, vehicleIds: { [$0.id] }) {
                try upsertVehicle($0, syncState: $1)
            }
        case FillUp.entityType:
            return try apply(record, syncState: syncState, as: FillUp.self, vehicleIds: { [$0.vehicleId] }) {
                try upsertFillUp($0, syncState: $1)
            }
        case ChargeSession.entityType:
            return try apply(record, syncState: syncState, as: ChargeSession.self, vehicleIds: { [$0.vehicleId] }) {
                try upsertChargeSession($0, syncState: $1)
            }
        case ServiceRecord.entityType:
            return try apply(record, syncState: syncState, as: ServiceRecord.self, vehicleIds: { [$0.vehicleId] }) {
                try upsertServiceRecord($0, linkedParts: [], syncState: $1)
            }
        case Expense.entityType:
            return try apply(record, syncState: syncState, as: Expense.self, vehicleIds: { [$0.vehicleId] }) {
                try upsertExpense($0, syncState: $1)
            }
        case Reminder.entityType:
            return try apply(record, syncState: syncState, as: Reminder.self, vehicleIds: { [$0.vehicleId] }) {
                try upsertReminder($0, syncState: $1)
            }
        case Station.entityType:
            return try apply(record, syncState: syncState, as: Station.self, vehicleIds: { _ in [] }) {
                try upsertStation($0, syncState: $1)
            }
        case Tariff.entityType:
            return try apply(record, syncState: syncState, as: Tariff.self,
                             vehicleIds: { $0.vehicleId.map { [$0] } ?? [] }) {
                try upsertTariff($0, syncState: $1)
            }
        case TireSet.entityType:
            return try apply(record, syncState: syncState, as: TireSet.self, vehicleIds: { [$0.vehicleId] }) {
                try upsertTireSet($0, syncState: $1)
            }
        case Attachment.entityType:
            return try apply(record, syncState: syncState, as: Attachment.self, vehicleIds: { _ in [] }) {
                try upsertAttachment($0, syncState: $1)
            }
        case Preferences.entityType:
            return try apply(record, syncState: syncState, as: Preferences.self, vehicleIds: { _ in [] }) {
                try upsertPreferences($0, syncState: $1)
            }
        default:
            return []
        }
    }

    /// Applies a pulled/merged record as `synced(scn)`.
    public func applyRemoteRecord(_ record: SyncRecord, scn: Int64) throws -> Set<UUID> {
        try applyRecord(record, syncState: .synced(scn: scn))
    }

    /// Recovers rows left `pushing` by a crashed or failed run: they return to
    /// `.dirty` so the next cycle picks them up (docs/SyncState.swift).
    public func recoverStuckPushes() throws {
        try database.write { db in
            for table in TankbookSchema.syncedTables {
                try db.execute(sql: "UPDATE \(table) SET syncState = 'dirty' WHERE syncState = 'pushing'")
            }
        }
    }

    /// S5: an entry pulled from another device references a vehicle this device
    /// deleted. The vehicle resurrects as ARCHIVED (not active) so the entry has
    /// a home and the user can delete again in one tap - nothing is lost
    /// silently (docs/SYNC.md S5).
    public func resurrectArchivedIfTombstoned(vehicleId: UUID) throws {
        try database.write { db in
            let stamp = Date().timeIntervalSinceReferenceDate
            try db.execute(sql: """
                UPDATE \(TankbookSchema.vehicle)
                SET deletedAt = NULL, archived = 1, archivedAt = ?, updatedAt = ?, syncState = 'dirty'
                WHERE id = ? AND deletedAt IS NOT NULL
                """, arguments: [stamp, stamp, vehicleId.uuidString])
        }
    }

    private func apply<E: SyncedEntity>(_ record: SyncRecord, syncState: SyncState, as type: E.Type,
                                        vehicleIds: (E) -> [UUID],
                                        upsert: (E, SyncState) throws -> Void) throws -> Set<UUID> {
        let envelope = PayloadEnvelope(entityType: record.entityType,
                                       schemaVersion: record.schemaVersion,
                                       payload: record.payload)
        var entity = try PayloadCodec.decode(envelope, as: E.self).entity
        if record.deleted, entity.deletedAt == nil { entity.deletedAt = record.clientUpdatedAt }
        try upsert(entity, syncState)
        return Set(vehicleIds(entity))
    }
}

// MARK: - Sync overwrite undo log (S1/S4)

extension TankbookRepository {
    /// Records a version a sync merge overwrote (docs/SYNC.md S1/S4: the losing
    /// version is kept for the 30-day undo window).
    public func recordSyncOverwrite(recordId: UUID, losingRecord: SyncRecord, at date: Date = Date()) throws {
        try database.write { db in
            let payloadJSON = try losingRecord.payload.jsonString()
            try db.execute(sql: """
                INSERT INTO \(TankbookSchema.syncOverwrite)
                    (id, recordId, entityType, losingPayload, losingUpdatedAt, replacedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    UUID.v7().uuidString,
                    recordId.uuidString,
                    losingRecord.entityType,
                    payloadJSON,
                    losingRecord.clientUpdatedAt.timeIntervalSinceReferenceDate,
                    date.timeIntervalSinceReferenceDate,
                ])
        }
    }

    /// The undo log, newest overwrite first.
    public func syncOverwrittenEntries() throws -> [SyncOverwrite] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, recordId, entityType, losingPayload, losingUpdatedAt, replacedAt
                FROM \(TankbookSchema.syncOverwrite)
                ORDER BY replacedAt DESC
                """)
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"] as String),
                      let recordId = UUID(uuidString: row["recordId"] as String),
                      let entityType = row["entityType"] as String?,
                      let payloadJSON = row["losingPayload"] as String?,
                      let payload = try? JSONValue.parse(payloadJSON) else {
                    return nil
                }
                return SyncOverwrite(
                    id: id,
                    recordId: recordId,
                    entityType: entityType,
                    losingPayload: payload,
                    losingUpdatedAt: Date(timeIntervalSinceReferenceDate: row["losingUpdatedAt"] as Double),
                    replacedAt: Date(timeIntervalSinceReferenceDate: row["replacedAt"] as Double))
            }
        }
    }
}

// MARK: - Sync payload memory (S9)

extension TankbookRepository {
    /// The last payload this device synced for a record, or nil when it has none
    /// (a record never synced, or the memory was never written). The `Vehicle`
    /// field-level merge diffs against it (docs/SYNC.md S9).
    public func lastSyncedPayload(for id: UUID) throws -> JSONValue? {
        try database.read { db in
            guard let json = try String.fetchOne(db, sql: """
                SELECT payload FROM \(TankbookSchema.syncPayloadMemory) WHERE id = ?
                """, arguments: [id.uuidString]) else {
                return nil
            }
            return try? JSONValue.parse(json)
        }
    }

    /// Persists the payload that now represents the server's state for a record
    /// (after a successful push or pull). Upsert: one memory row per record id.
    public func recordSynced(id: UUID, payload: JSONValue) throws {
        let json = try payload.jsonString()
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO \(TankbookSchema.syncPayloadMemory) (id, payload)
                VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                """, arguments: [id.uuidString, json])
        }
    }
}

/// The persisted `SyncPayloadMemory` (docs/SYNC.md S9: the field-level merge
/// must survive the process, or a relaunched device claims every field changed
/// and can revert another device's edit - hard rule 13). Device-local, never
/// synced, lives in the same protected database as the records it remembers.
///
/// `@unchecked Sendable` like `InMemorySyncPayloadMemory`: the GRDB writer is
/// thread-safe and this class is stateless beyond it, so the honest isolation
/// is the unchecked conformance the memory seam already uses.
public final class DatabaseSyncPayloadMemory: SyncPayloadMemory, @unchecked Sendable {
    private let repository: TankbookRepository

    public init(repository: TankbookRepository) {
        self.repository = repository
    }

    public func lastSyncedPayload(for id: UUID) -> JSONValue? {
        try? repository.lastSyncedPayload(for: id)
    }

    public func recordSynced(id: UUID, payload: JSONValue) {
        try? repository.recordSynced(id: id, payload: payload)
    }
}

// MARK: - The record stream (restore / backup snapshot)

extension TankbookRepository {
    /// Every record across the synced tables - live and tombstoned - as the sync
    /// engine reads them: the record stream a backup snapshot is (docs/SYNC.md:
    /// "backups are a snapshot of records at an SCN"). Device-local sync
    /// bookkeeping (`syncState`/`syncScn`) is absent by construction, and the
    /// payloads are re-encoded from the decoded entity so the in-transit
    /// `fieldVersions` key never leaks in - two devices hold the same data iff
    /// their records are equal here (the restore hash-equals-origin check).
    public func allRecords() throws -> [SyncRecord] {
        try database.read { db in
            var records: [SyncRecord] = []
            records += try fetchAllRecords(VehicleRow.self, entityType: Vehicle.entityType, in: db) { $0.vehicle }
            records += try fetchAllRecords(FillUpRow.self, entityType: FillUp.entityType, in: db) { $0.fillUp }
            records += try fetchAllRecords(ChargeSessionRow.self, entityType: ChargeSession.entityType, in: db) { $0.chargeSession }
            records += try allServiceRecords(in: db)
            records += try fetchAllRecords(ExpenseRow.self, entityType: Expense.entityType, in: db) { $0.expense }
            records += try fetchAllRecords(ReminderRow.self, entityType: Reminder.entityType, in: db) { $0.reminder }
            records += try fetchAllRecords(StationRow.self, entityType: Station.entityType, in: db) { $0.station }
            records += try fetchAllRecords(TariffRow.self, entityType: Tariff.entityType, in: db) { $0.tariff }
            records += try fetchAllRecords(TireSetRow.self, entityType: TireSet.entityType, in: db) { $0.tireSet }
            records += try fetchAllRecords(AttachmentRow.self, entityType: Attachment.entityType, in: db) { $0.attachment }
            records += try fetchAllRecords(PreferencesRow.self, entityType: Preferences.entityType, in: db) { $0.preferences }
            return records
        }
    }

    private func fetchAllRecords<R: FetchableRecord & TableRecord, E: SyncedEntity>(
        _ type: R.Type, entityType: String, in db: Database, entity: (R) -> E
    ) throws -> [SyncRecord] {
        try R.fetchAll(db).map { row in
            let value = entity(row)
            return SyncRecord(
                id: value.id,
                entityType: entityType,
                schemaVersion: PayloadCodec.currentSchemaVersion,
                payload: try PayloadCodec.encode(value).payload,
                clientUpdatedAt: value.updatedAt,
                deleted: value.deletedAt != nil
            )
        }
    }

    private func allServiceRecords(in db: Database) throws -> [SyncRecord] {
        let services = try attachServiceItems(ServiceRecordRow.fetchAll(db), in: db)
        return services.map { service in
            SyncRecord(
                id: service.id,
                entityType: ServiceRecord.entityType,
                schemaVersion: PayloadCodec.currentSchemaVersion,
                payload: (try? PayloadCodec.encode(service).payload) ?? .object([:]),
                clientUpdatedAt: service.updatedAt,
                deleted: service.deletedAt != nil
            )
        }
    }
}

// MARK: - Domain re-validation after merge (S3)

extension TankbookRepository {
    /// Re-runs timeline validation for the given vehicles and writes the amber
    /// `ConflictState` onto any entry that broke (docs/SYNC.md S3: the transport
    /// accepted both records; the domain is what flags one). Returns the number
    /// of entries newly flagged.
    @discardableResult
    public func revalidateTimeline(vehicleIds: Set<UUID>) throws -> Int {
        var flagged = 0
        for vehicleId in vehicleIds {
            guard let vehicle = try vehicle(id: vehicleId) else { continue }
            let entries = try liveEntries(forVehicle: vehicleId)
            let attachments = try liveAttachments()
            let validations = TimelineValidator.validate(entries: entries, vehicle: vehicle, attachments: attachments)
            let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            try database.write { db in
                for validation in validations {
                    guard let entry = byID[validation.entryID],
                          entry.conflict != validation.conflict,
                          let table = entryTable(entry) else { continue }
                    try db.execute(sql: """
                        UPDATE \(table) SET conflict = ?, syncState = 'dirty' WHERE id = ?
                        """, arguments: [try encodeJSON(validation.conflict), entry.id.uuidString])
                    flagged += 1
                }
            }
        }
        return flagged
    }

    private func entryTable(_ entry: any Entry) -> String? {
        switch entry {
        case is FillUp: TankbookSchema.fillUp
        case is ChargeSession: TankbookSchema.chargeSession
        case is ServiceRecord: TankbookSchema.serviceRecord
        case is Expense: TankbookSchema.expense
        default: nil
        }
    }
}
