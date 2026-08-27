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
        guard !fills.isEmpty else { return 0 }
        let records = fills.map { ArchiveImportRecord.fillUp($0) }
        try applyArchiveRecords(records, syncState: .dirty)
        return fills.count
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
    }
}
