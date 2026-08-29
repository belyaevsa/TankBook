import Foundation
import GRDB

// The archive's persistence surface (docs/SCHEMA.md -> "Backup format"): the
// tombstone-INCLUSIVE reads the writer needs (an export carries every tombstone
// - hard rule 8, nothing lost silently) and the whole-or-nothing apply the
// reader needs (a corrupt archive imports nothing and leaves the repository as
// it was).

/// A fully-validated archive record, typed back to its domain entity. The
/// reader produces these BEFORE any write happens; the repository commits them
/// in one transaction or not at all.
public enum ArchiveImportRecord: Sendable {
    case vehicle(Vehicle)
    case fillUp(FillUp)
    case chargeSession(ChargeSession)
    case serviceRecord(ServiceRecord)
    case expense(Expense)
    case reminder(Reminder)
    case station(Station)
    case tariff(Tariff)
    case attachment(Attachment)

    /// The entry this record carries, if any (PJ.11: the four entry types are
    /// the ones the timeline validator stamps).
    var entryValue: (any Entry)? {
        switch self {
        case .fillUp(let fill): fill
        case .chargeSession(let charge): charge
        case .serviceRecord(let service): service
        case .expense(let expense): expense
        default: nil
        }
    }

    /// This record with `conflict` replaced (PJ.11). Non-entry records return
    /// themselves unchanged.
    func stampingConflict(_ conflict: ConflictState) -> ArchiveImportRecord {
        switch self {
        case .fillUp(let fill):
            var copy = fill
            copy.conflict = conflict
            return .fillUp(copy)
        case .chargeSession(let charge):
            var copy = charge
            copy.conflict = conflict
            return .chargeSession(copy)
        case .serviceRecord(let service):
            var copy = service
            copy.conflict = conflict
            return .serviceRecord(copy)
        case .expense(let expense):
            var copy = expense
            copy.conflict = conflict
            return .expense(copy)
        default:
            return self
        }
    }

    /// Whether two records are the same underlying entry (same kind, same id).
    /// Used to replace a stamped copy back into the batch by value - the
    /// records are structs, so identity comparison needs the payload.
    func isSameRecord(as other: ArchiveImportRecord) -> Bool {
        switch (self, other) {
        case (.fillUp(let lhs), .fillUp(let rhs)): lhs.id == rhs.id
        case (.chargeSession(let lhs), .chargeSession(let rhs)): lhs.id == rhs.id
        case (.serviceRecord(let lhs), .serviceRecord(let rhs)): lhs.id == rhs.id
        case (.expense(let lhs), .expense(let rhs)): lhs.id == rhs.id
        case (.vehicle(let lhs), .vehicle(let rhs)): lhs.id == rhs.id
        case (.reminder(let lhs), .reminder(let rhs)): lhs.id == rhs.id
        case (.station(let lhs), .station(let rhs)): lhs.id == rhs.id
        case (.tariff(let lhs), .tariff(let rhs)): lhs.id == rhs.id
        case (.attachment(let lhs), .attachment(let rhs)): lhs.id == rhs.id
        default: false
        }
    }
}

extension TankbookRepository {

    // MARK: - Tombstone-inclusive reads (the writer's view)

    /// Every row of the table, tombstones included, for `vehicleId`. The `live`
    /// reads hide tombstones; an export must not.
    func rowsIncludingDeleted<Record: FetchableRecord & TableRecord>(
        _ type: Record.Type, forVehicle vehicleId: UUID, in db: Database
    ) throws -> [Record] {
        try Record
            .filter(Column("vehicleId") == vehicleId.uuidString)
            .order(Column("date"), Column("createdAt"))
            .fetchAll(db)
    }

    public func vehicleIncludingDeleted(id: UUID) throws -> Vehicle? {
        try database.read { db in
            try VehicleRow.fetchOne(db, key: id.uuidString)?.vehicle
        }
    }

    public func fillUpsIncludingDeleted(forVehicle vehicleId: UUID) throws -> [FillUp] {
        try database.read { db in
            try rowsIncludingDeleted(FillUpRow.self, forVehicle: vehicleId, in: db).map(\.fillUp)
        }
    }

    public func chargeSessionsIncludingDeleted(forVehicle vehicleId: UUID) throws -> [ChargeSession] {
        try database.read { db in
            try rowsIncludingDeleted(ChargeSessionRow.self, forVehicle: vehicleId, in: db).map(\.chargeSession)
        }
    }

    public func serviceRecordsIncludingDeleted(forVehicle vehicleId: UUID) throws -> [ServiceRecord] {
        try database.read { db in
            try attachServiceItems(rowsIncludingDeleted(ServiceRecordRow.self, forVehicle: vehicleId, in: db), in: db)
        }
    }

    public func expensesIncludingDeleted(forVehicle vehicleId: UUID) throws -> [Expense] {
        try database.read { db in
            try rowsIncludingDeleted(ExpenseRow.self, forVehicle: vehicleId, in: db).map(\.expense)
        }
    }

    public func remindersIncludingDeleted(forVehicle vehicleId: UUID) throws -> [Reminder] {
        try database.read { db in
            try ReminderRow
                .filter(Column("vehicleId") == vehicleId.uuidString)
                .order(Column("createdAt"))
                .fetchAll(db)
                .map(\.reminder)
        }
    }

    /// Every tariff row, tombstones included (tariffs are vehicle-scoped or
    /// household-wide; the writer picks what belongs to a car).
    public func tariffsIncludingDeleted() throws -> [Tariff] {
        try database.read { db in
            try TariffRow.order(Column("createdAt")).fetchAll(db).map(\.tariff)
        }
    }

    public func stationsIncludingDeleted() throws -> [Station] {
        try database.read { db in
            try StationRow.order(Column("createdAt")).fetchAll(db).map(\.station)
        }
    }

    public func attachmentsIncludingDeleted() throws -> [Attachment] {
        try database.read { db in
            try AttachmentRow.order(Column("createdAt")).fetchAll(db).map(\.attachment)
        }
    }

    // MARK: - Whole-or-nothing apply

    /// Commits import-derived fills (the review list's kept rows, P5.5b) into
    /// one transaction. Reuses the archive apply path so the two user-held
    /// imports share the same atomic, tombstone-safe write; rows land `.dirty`
    /// (a user-held import is local data that must sync). Returns the count
    /// written. This is the ONLY write the import flow performs - building the
    /// preview, computing the figures and cancelling all happen without touching
    /// the repository (F6a: nothing is written until the user confirms).
    @discardableResult
    public func commitImportFills(_ fills: [FillUp], source: String) throws -> Int {
        try commitImport(fills.map { ArchiveImportRecord.fillUp($0) }, source: source)
    }

    /// Commits import-derived records - fills, services and expenses, the
    /// review list's kept rows (PJ.9: a non-fuel row commits as what it is) -
    /// in one transaction. Same whole-or-nothing, tombstone-safe path as the
    /// fills-only form; rows land `.dirty`. Returns the count written.
    ///
    /// PJ.11: the commit re-stamps every incoming entry's `conflict` from
    /// `TimelineValidator` against the merged timeline (the target car's
    /// existing entries plus the incoming records). The classifier stamps the
    /// fills it partitions for the review list; this re-stamp is the
    /// authoritative write-time check and covers the noFuel service/expense
    /// records too, so a row the user edited in the review list can never
    /// commit unflagged (F9a: checked on every write, not just capture).
    @discardableResult
    public func commitImport(_ records: [ArchiveImportRecord], source: String) throws -> Int {
        guard !records.isEmpty else { return 0 }
        try database.write { db in
            let stamped = try stampingImportConflicts(records: records, in: db)
            try apply(stamped, syncState: .dirty, in: db)
        }
        return records.count
    }

    /// Commits a fully-validated archive in ONE transaction. The reader has
    /// already schema-validated and typed-decoded every record, so nothing here
    /// can fail on meaning - only on the database itself. If any row throws,
    /// GRDB rolls the whole batch back: a partially applied archive is worse
    /// than a stale one (the same rule as the catalog pack and remote config).
    ///
    /// Rows land `.dirty` (a user-held import is local data that must sync),
    /// preserving any existing base SCN so a re-import into a repository that
    /// already holds the car does not disturb its sync base.
    public func applyArchiveRecords(_ records: [ArchiveImportRecord],
                                    syncState: SyncState = .dirty) throws {
        try database.write { db in
            try apply(records, syncState: syncState, in: db)
        }
    }

    /// The `applyArchiveRecords` body, hoisted so `commitImport` can stamp
    /// conflicts and write in the SAME transaction (PJ.11) - the stamp must see
    /// the existing rows, and the write must be atomic with it.
    private func apply(_ records: [ArchiveImportRecord],
                       syncState: SyncState, in db: Database) throws {
        for record in records {
            switch record {
            case .vehicle(let vehicle):
                var row = VehicleRow(vehicle: vehicle, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.vehicle, id: vehicle.id, in: db)
                try row.save(db)
            case .fillUp(let fillUp):
                var row = FillUpRow(fillUp: fillUp, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.fillUp, id: fillUp.id, in: db)
                try row.save(db)
            case .chargeSession(let charge):
                var row = ChargeSessionRow(chargeSession: charge, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.chargeSession,
                                                id: charge.id, in: db)
                try row.save(db)
            case .serviceRecord(let service):
                var row = ServiceRecordRow(service: service, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.serviceRecord,
                                                id: service.id, in: db)
                try row.save(db)
                try db.execute(sql: "DELETE FROM \(TankbookSchema.serviceItem) WHERE serviceRecordId = ?",
                               arguments: [service.id.uuidString])
                for (position, item) in service.items.enumerated() {
                    try ServiceItemRow(serviceRecordId: service.id, position: position, item: item).insert(db)
                }
            case .expense(let expense):
                var row = ExpenseRow(expense: expense, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.expense, id: expense.id, in: db)
                try row.save(db)
            case .reminder(let reminder):
                var row = ReminderRow(reminder: reminder, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.reminder, id: reminder.id, in: db)
                try row.save(db)
            case .station(let station):
                var row = StationRow(station: station, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.station, id: station.id, in: db)
                try row.save(db)
            case .tariff(let tariff):
                var row = TariffRow(tariff: tariff, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.tariff, id: tariff.id, in: db)
                try row.save(db)
            case .attachment(let attachment):
                var row = AttachmentRow(attachment: attachment, syncState: syncState)
                row.syncScn = try preservingScn(syncState, table: TankbookSchema.attachment,
                                                id: attachment.id, in: db)
                try row.save(db)
            }
        }
    }

    /// PJ.11: the write-time stamp. Groups the incoming entry records by
    /// vehicle, reads each car's existing live entries, validates the merged
    /// timeline once per car, and returns the records with `conflict` replaced
    /// by the validator's verdict. Records for a car not in the database (a
    /// broken archive, or a restore racing the import) are left as they came.
    private func stampingImportConflicts(records: [ArchiveImportRecord],
                                         in db: Database) throws -> [ArchiveImportRecord] {
        var byVehicle: [UUID: [ArchiveImportRecord]] = [:]
        for record in records {
            guard let entry = record.entryValue else { continue }
            byVehicle[entry.vehicleId, default: []].append(record)
        }
        guard !byVehicle.isEmpty else { return records }

        var stamped = records
        for (_, vehicleRecords) in byVehicle {
            guard let firstEntry = vehicleRecords.compactMap(\.entryValue).first,
                  let vehicle = try VehicleRow.fetchOne(db, key: firstEntry.vehicleId.uuidString)?.vehicle else {
                continue
            }
            let existing = try liveEntries(forVehicle: firstEntry.vehicleId, in: db)
            let incoming = vehicleRecords.compactMap(\.entryValue)
            let validations = TimelineValidator.validate(entries: existing + incoming, vehicle: vehicle)
            let byID = Dictionary(uniqueKeysWithValues: validations.map { ($0.entryID, $0) })
            for record in vehicleRecords {
                guard let entry = record.entryValue,
                      let validation = byID[entry.id],
                      let position = stamped.firstIndex(where: { $0.isSameRecord(as: record) }) else { continue }
                stamped[position] = record.stampingConflict(validation.conflict)
            }
        }
        return stamped
    }

    private func liveEntries(forVehicle vehicleId: UUID, in db: Database) throws -> [any Entry] {
        let predicate = Column("vehicleId") == vehicleId.uuidString && Column("deletedAt") == nil
        let fills: [any Entry] = try FillUpRow.filter(predicate).fetchAll(db).map(\.fillUp)
        let charges: [any Entry] = try ChargeSessionRow.filter(predicate).fetchAll(db).map(\.chargeSession)
        let services: [any Entry] = try ServiceRecordRow.filter(predicate).fetchAll(db).map(\.service)
        let expenses: [any Entry] = try ExpenseRow.filter(predicate).fetchAll(db).map(\.expense)
        return fills + charges + services + expenses
    }
}
