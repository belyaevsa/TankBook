import Foundation
import Testing
@testable import TankbookCore

// Persistence tests for P0.4 (GRDB setup + migrations). Every test opens its
// own in-memory database, so tests are fully independent and parallel-safe.

private let timestamp = Date(timeIntervalSince1970: 1_752_000_000)

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func makeRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

// MARK: - Fixtures

private func makeVehicle(id: UUID = UUID.v7()) -> Vehicle {
    Vehicle(
        id: id,
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        name: "Volvo V60",
        make: "Volvo",
        model: "V60",
        year: 2021,
        plate: "ABC-123",
        powertrain: .hybrid,
        fuelKinds: [.petrol95, .electricity],
        tankCapacityL: 71,
        batteryCapacityKWh: nil,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil,
        archived: false,
        paceLimitKmPerDay: 1500)
}

private func makeFillUp(
    id: UUID = UUID.v7(),
    vehicleId: UUID,
    date: Date = timestamp,
    money: Money? = Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
    unitPrice: Decimal? = decimal("1.679")
) -> FillUp {
    FillUp(
        id: id, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: 82_400,
        money: money, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil,
        volumeL: 42.3, unitPrice: unitPrice, fuelKind: .petrol95, fuelGrade: nil,
        isFull: true, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

private func makeCharge(vehicleId: UUID, date: Date = timestamp) -> ChargeSession {
    ChargeSession(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: 18_000, money: nil,
        note: "Free destination charging", attachments: [], provenance: .fiscalQR,
        conflict: .none, purchaseGroupId: nil,
        energyKWh: 43.2, unitPrice: nil, chargeType: .dcPublic, provider: "Ionity",
        tariffId: nil, durationMin: 42, socStartPct: 18, socEndPct: 92,
        extraction: ExtractionMeta(fields: [:], pipeline: "fiscal-qr"))
}

private func makeExpense(id: UUID = UUID.v7(), vehicleId: UUID, date: Date = timestamp) -> Expense {
    Expense(
        id: id, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: nil,
        money: Money(amount: decimal("540.00"), currency: .eur, homeCurrency: .eur),
        note: nil, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        category: .insurance, title: "Annual insurance",
        recurrence: RecurrenceRule(everyMonths: 12, anchorDate: timestamp),
        installedInServiceId: nil)
}

// MARK: - Migration

@Test func migrateFromEmptyCreatesAllTablesAndIndexes() throws {
    let database = try TankbookDatabase.inMemory()
    let tables = Set(try database.tableNames())
    for table in TankbookSchema.syncedTables + [TankbookSchema.exchangeRate] {
        #expect(tables.contains(table), "missing table \(table)")
    }
    #expect(tables.contains("grdb_migrations"))   // GRDB's own bookkeeping

    let indexes = Set(try database.indexNames())
    for table in TankbookSchema.entryTables {
        for suffix in ["vehicle_date", "vehicle_odometer", "live", "sync"] {
            #expect(indexes.contains("idx_\(table)_\(suffix)"), "missing index idx_\(table)_\(suffix)")
        }
    }
    for table in TankbookSchema.syncedTables where !TankbookSchema.entryTables.contains(table) {
        #expect(indexes.contains("idx_\(table)_sync"), "missing index idx_\(table)_sync")
    }
    #expect(indexes.contains("idx_exchangeRate_date"))
}

@Test func migratingAnAlreadyMigratedDatabaseIsNoOp() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)
    let tablesBefore = try repo.database.tableNames()

    try repo.database.migrator.migrate(repo.database.writer)

    #expect(try repo.database.tableNames() == tablesBefore)
    #expect(try repo.liveVehicles().count == 1)
    #expect(try repo.vehicle(id: vehicle.id) == vehicle)
}

// MARK: - CRUD round-trips (catch Decimal / date / enum mapping bugs)

@Test func vehicleCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)
    #expect(try repo.liveVehicles() == [vehicle])
    #expect(try repo.vehicle(id: vehicle.id) == vehicle)
}

/// `initialOdometer` is the "Current odometer" typed on Add car, and the whole
/// reason the field exists is that the value used to be discarded (docs/SCHEMA.md,
/// Vehicle). Asserted explicitly rather than left to the round-trip above, whose
/// `makeVehicle()` fixture could stop setting it without anything failing.
@Test func vehicleInitialOdometerSurvivesPersistence() throws {
    let repo = try makeRepository()
    var vehicle = makeVehicle()
    vehicle.initialOdometer = 119_486

    try repo.upsertVehicle(vehicle)

    #expect(try repo.vehicle(id: vehicle.id)?.initialOdometer == 119_486)
}

/// It is optional: a car saved with no odometer reading is valid, because the
/// implausible-reading warning never blocks save (docs/ERRORS.md -> Add car).
@Test func vehicleWithoutInitialOdometerRoundTripsAsNil() throws {
    let repo = try makeRepository()
    var vehicle = makeVehicle()
    vehicle.initialOdometer = nil

    try repo.upsertVehicle(vehicle)

    #expect(try repo.vehicle(id: vehicle.id)?.initialOdometer == nil)
}

@Test func fillUpCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let fillUp = FillUp(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, date: timestamp, odometer: 82_400,
        money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
        note: "Shell, A4 exit", attachments: [UUID.v7(), UUID.v7()],
        provenance: .receiptScan, conflict: .flagged(kind: .pace, detectedAt: timestamp),
        purchaseGroupId: UUID.v7(),
        volumeL: 42.3, unitPrice: decimal("1.679"), fuelKind: .petrol95,
        fuelGrade: "V-Power", isFull: true, tankLevelAfterPct: 100, stationId: UUID.v7(),
        crossCheck: .mismatch(field: .lineItem(2)),
        extraction: ExtractionMeta(
            fields: [.total: FieldExtraction(cropRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1),
                                             confidence: 0.98, userCorrected: true)],
            pipeline: "vision+rules v3"))
    try repo.upsertFillUp(fillUp)
    #expect(try repo.liveFillUps(forVehicle: vehicleId) == [fillUp])
}

@Test func chargeSessionCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let charge = ChargeSession(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, date: timestamp, odometer: 18_000,
        money: Money(amount: decimal("6.63"), currency: .eur, homeCurrency: .eur),
        note: "Ionity stop", attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil,
        energyKWh: 43.2, unitPrice: decimal("0.39"), chargeType: .dcPublic,
        provider: "Ionity", tariffId: nil, durationMin: 42, socStartPct: 18, socEndPct: 92,
        extraction: ExtractionMeta(fields: [.energy: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false)],
                                   pipeline: "fiscal-qr"))
    try repo.upsertChargeSession(charge)
    #expect(try repo.liveChargeSessions(forVehicle: vehicleId) == [charge])
}

@Test func serviceRecordCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let service = ServiceRecord(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, date: timestamp, odometer: 90_000, money: nil,
        note: "Annual service", attachments: [UUID.v7()],
        provenance: .import(source: "Fuelio"), conflict: .flagged(kind: .order, detectedAt: timestamp),
        purchaseGroupId: UUID.v7(),
        vendor: "Bosch Service",
        items: [
            ServiceItem(title: "Oil change", category: .oil,
                        cost: Money(amount: decimal("89.00"), currency: .eur, homeCurrency: .eur),
                        partNumber: "MANN W 712/75",
                        lifetime: ServiceItem.Lifetime(km: 15_000, months: 12)),
            ServiceItem(title: "Cabin filter", category: .filters,
                        cost: nil, partNumber: nil,
                        lifetime: ServiceItem.Lifetime(km: nil, months: nil)),
        ],
        usedParts: [UUID.v7()], tireSetId: nil, proposedReminderId: UUID.v7())
    try repo.upsertServiceRecord(service)
    #expect(try repo.liveServiceRecords(forVehicle: vehicleId) == [service])
}

@Test func expenseCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let expense = makeExpense(vehicleId: vehicleId)
    try repo.upsertExpense(expense)
    #expect(try repo.liveExpenses(forVehicle: vehicleId) == [expense])
}

@Test func reminderCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let reminder = Reminder(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, title: "Oil change", category: .oil,
        dueDate: timestamp.addingTimeInterval(3_600), dueOdometer: 105_000,
        recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12),
        sourceEntryId: UUID.v7(), status: .done(entryId: UUID.v7()))
    try repo.upsertReminder(reminder)
    #expect(try repo.liveReminders(forVehicle: vehicleId) == [reminder])
}

@Test func stationCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let station = Station(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        name: "Shell Tiergarten", brand: "Shell",
        location: GeoCoordinate(latitude: 52.51, longitude: 13.35), favorite: true,
        defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: "V-Power"),
        lastUsedAt: timestamp)
    try repo.upsertStation(station)
    #expect(try repo.liveStations() == [station])
}

@Test func tariffCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let tariff = Tariff(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: nil, name: "Home night rate",
        pricePerKWh: decimal("0.2395"), currency: .eur, validFrom: timestamp)
    try repo.upsertTariff(tariff)
    #expect(try repo.liveTariffs() == [tariff])
}

@Test func tireSetCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let tireSet = TireSet(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, name: "Winter Nokian", purchaseExpenseId: UUID.v7())
    try repo.upsertTireSet(tireSet)
    #expect(try repo.liveTireSets(forVehicle: vehicleId) == [tireSet])
}

@Test func attachmentCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let attachment = Attachment(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        kind: .pdf,
        file: LocalFileRef(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                           relativePath: "pdfs/2026/07/9f86d081.pdf"),
        extractedTimestamp: timestamp, ocrText: "SHELL 71.02 42.30 1.679")
    try repo.upsertAttachment(attachment)
    #expect(try repo.liveAttachments() == [attachment])
}

@Test func preferencesCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let preferences = Preferences(
        createdAt: timestamp, updatedAt: timestamp,
        notifications: Preferences.Notifications(reminders: true, anomalies: false, monthlySummary: true),
        eagerMediaOnWiFi: true, defaultVehicleId: UUID.v7(), proFeedbackDiagnostics: true)
    try repo.upsertPreferences(preferences)
    #expect(try repo.livePreferences() == preferences)
}

@Test func exchangeRateCRUDRoundTrip() throws {
    let repo = try makeRepository()
    let rate = ExchangeRate(base: .eur, quote: .pln, date: timestamp,
                            rate: decimal("4.2706"), source: .cis)
    try repo.upsertExchangeRate(rate)
    #expect(try repo.exchangeRate(base: .eur, quote: .pln, on: timestamp) == rate)
    #expect(try repo.exchangeRate(base: .eur, quote: .usd, on: timestamp) == nil)
}

// MARK: - Decimal fidelity (no floating-point drift anywhere)

@Test func decimalFidelityExactRoundTrip() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))

    // "1.679", "289.50", and "0.1 + 0.2" must come back bit-exact:
    let fill1679 = makeFillUp(vehicleId: vehicleId,
                              money: Money(amount: decimal("1.679"), currency: .eur, homeCurrency: .eur),
                              unitPrice: decimal("1.679"))
    let fill289 = makeFillUp(id: UUID.v7(), vehicleId: vehicleId, date: timestamp.addingTimeInterval(3_600),
                             money: Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
                                 .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: timestamp, source: .ecb)),
                             unitPrice: decimal("6.85"))
    let fillSum = makeFillUp(id: UUID.v7(), vehicleId: vehicleId, date: timestamp.addingTimeInterval(7_200),
                             money: Money(amount: decimal("0.1") + decimal("0.2"), currency: .eur, homeCurrency: .eur),
                             unitPrice: nil)
    try repo.upsertFillUp(fill1679)
    try repo.upsertFillUp(fill289)
    try repo.upsertFillUp(fillSum)

    let read = try repo.liveFillUps(forVehicle: vehicleId)
    #expect(read.count == 3)
    let read1679 = read.first { $0.id == fill1679.id }!
    #expect(read1679.unitPrice == decimal("1.679"))
    #expect(read1679.money?.amount == decimal("1.679"))
    let read289 = read.first { $0.id == fill289.id }!
    #expect(read289.money == fill289.money)                     // full snapshot pair round-trips
    #expect(read289.money?.homeAmount == decimal("67.79"))      // 289.50 / 4.2706, exactly
    let readSum = read.first { $0.id == fillSum.id }!
    #expect(readSum.money?.amount == decimal("0.3"))            // 0.1 + 0.2 stays 0.3

    // Long-precision decimals on non-entry money (service items, tariffs):
    let tariff = Tariff(id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
                        vehicleId: nil, name: "Night rate",
                        pricePerKWh: decimal("12.34567890123456789"), currency: .eur, validFrom: timestamp)
    try repo.upsertTariff(tariff)
    #expect(try repo.liveTariffs().first?.pricePerKWh == decimal("12.34567890123456789"))

    let rate = ExchangeRate(base: .eur, quote: .rub, date: timestamp,
                            rate: decimal("93.8412"), source: .cis)
    try repo.upsertExchangeRate(rate)
    #expect(try repo.exchangeRate(base: .eur, quote: .rub, on: timestamp)?.rate == decimal("93.8412"))
}

// MARK: - Soft delete / restore

@Test func softDeleteHidesLiveRowsAndRestoreBringsBack() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let fillUp = makeFillUp(vehicleId: vehicleId)
    let expense = makeExpense(vehicleId: vehicleId)
    try repo.upsertFillUp(fillUp)
    try repo.upsertExpense(expense)

    try repo.softDeleteFillUp(id: fillUp.id)

    #expect(try repo.liveFillUps(forVehicle: vehicleId).isEmpty)
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1)  // tombstone stays in the table
    #expect(try repo.liveExpenses(forVehicle: vehicleId).count == 1)  // untouched sibling

    try repo.restoreFillUp(id: fillUp.id)
    let restored = try repo.liveFillUps(forVehicle: vehicleId).first!
    var expected = fillUp
    expected.updatedAt = restored.updatedAt   // restore is an edit: updatedAt bumped
    #expect(restored == expected)
    #expect(restored.deletedAt == nil)
}

@Test func vehicleSoftDeleteCascadesTombstonesAndRestoreMatches() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let fillUp = makeFillUp(vehicleId: vehicleId)
    let reminder = Reminder(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, title: "Winter tires", category: .tires,
        dueDate: nil, dueOdometer: nil, recurrence: nil, sourceEntryId: nil,
        status: .scheduled)
    try repo.upsertFillUp(fillUp)
    try repo.upsertReminder(reminder)

    try repo.softDeleteVehicle(id: vehicleId)

    #expect(try repo.liveVehicles().isEmpty)
    #expect(try repo.liveFillUps(forVehicle: vehicleId).isEmpty)
    #expect(try repo.liveReminders(forVehicle: vehicleId).isEmpty)
    // Tombstoned, not physically gone:
    #expect(try repo.rowCount(in: TankbookSchema.vehicle) == 1)
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1)
    #expect(try repo.rowCount(in: TankbookSchema.reminder) == 1)

    try repo.restoreVehicle(id: vehicleId)

    var expectedVehicle = makeVehicle(id: vehicleId)
    expectedVehicle.updatedAt = try repo.vehicle(id: vehicleId)!.updatedAt
    #expect(try repo.vehicle(id: vehicleId) == expectedVehicle)
    let restoredFill = try repo.liveFillUps(forVehicle: vehicleId).first!
    var expectedFill = fillUp
    expectedFill.updatedAt = restoredFill.updatedAt
    #expect(restoredFill == expectedFill)
    let restoredReminder = try repo.liveReminders(forVehicle: vehicleId).first!
    var expectedReminder = reminder
    expectedReminder.updatedAt = restoredReminder.updatedAt
    #expect(restoredReminder == expectedReminder)
}

// MARK: - Tombstone purge (30-day grace)

@Test func tombstonePurgeHonorsGracePeriod() throws {
    let repo = try makeRepository()

    // Old vehicle: tombstoned 40 days ago - fully purged.
    let oldVehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: oldVehicleId))
    try repo.upsertFillUp(makeFillUp(vehicleId: oldVehicleId))
    try repo.softDeleteVehicle(id: oldVehicleId, at: Date(timeIntervalSinceNow: -40 * 86_400))

    // Fresh vehicle: tombstoned now - inside the grace period, kept.
    let freshVehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: freshVehicleId))
    try repo.upsertFillUp(makeFillUp(vehicleId: freshVehicleId))
    try repo.softDeleteVehicle(id: freshVehicleId, at: Date())

    try repo.purgeTombstones(olderThan: Date(timeIntervalSinceNow: -29 * 86_400))

    #expect(try repo.rowCount(in: TankbookSchema.vehicle) == 1)  // old gone, fresh kept
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1)
    #expect(try repo.liveVehicles().isEmpty)                    // fresh is still tombstoned
    #expect(try repo.liveFillUps(forVehicle: freshVehicleId).isEmpty)
}

@Test func purgeKeepsVehicleTombstoneWhileAnyEntryIsLive() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let fillUp = makeFillUp(vehicleId: vehicleId)
    try repo.upsertFillUp(fillUp)

    try repo.softDeleteVehicle(id: vehicleId, at: Date(timeIntervalSinceNow: -40 * 86_400))
    try repo.restoreFillUp(id: fillUp.id)   // entry live again under a tombstoned vehicle

    try repo.purgeTombstones(olderThan: Date())

    #expect(try repo.rowCount(in: TankbookSchema.vehicle) == 1)  // kept: cascade would lose the live entry
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 1)
    #expect(try repo.liveVehicles().isEmpty)                    // vehicle itself still tombstoned
}

// MARK: - Foreign keys

@Test func foreignKeyBlocksEntryWithUnknownVehicle() throws {
    let repo = try makeRepository()
    do {
        try repo.upsertFillUp(makeFillUp(vehicleId: UUID.v7()))
        Issue.record("Expected a foreign-key failure for an unknown vehicleId")
    } catch {
        // Expected: the orphan row is rejected, nothing is written.
    }
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 0)
}

@Test func foreignKeyCascadesOnHardVehicleDelete() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicleId))
    try repo.upsertReminder(Reminder(
        id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        vehicleId: vehicleId, title: "Brakes", category: .brakes,
        dueDate: nil, dueOdometer: nil, recurrence: nil, sourceEntryId: nil, status: .scheduled))
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 1)

    try repo.hardDeleteVehicle(id: vehicleId)

    #expect(try repo.rowCount(in: TankbookSchema.vehicle) == 0)
    #expect(try repo.rowCount(in: TankbookSchema.fillUp) == 0)    // cascaded
    #expect(try repo.rowCount(in: TankbookSchema.reminder) == 0)  // cascaded
}

// MARK: - Sync queue + Log union

@Test func dirtyRowsQueueNewWritesAndTombstones() throws {
    let repo = try makeRepository()
    #expect(try repo.fetchDirtyRows().isEmpty)

    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId), syncState: .synced(scn: 5))
    #expect(try repo.fetchDirtyRows().isEmpty)   // synced rows are not queued

    let fillUp = makeFillUp(vehicleId: vehicleId)
    try repo.upsertFillUp(fillUp)
    var dirty = try repo.fetchDirtyRows()
    #expect(dirty.count == 1)
    #expect(dirty.first?.entityType == "fillUp")
    #expect(dirty.first?.id == fillUp.id)
    #expect(dirty.first?.deleted == false)

    try repo.softDeleteFillUp(id: fillUp.id)
    dirty = try repo.fetchDirtyRows()
    #expect(dirty.count == 1)
    #expect(dirty.first?.deleted == true)
}

@Test func liveEntriesUnionsEntryTypesSortedByDate() throws {
    let repo = try makeRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeVehicle(id: vehicleId))
    let fill = makeFillUp(vehicleId: vehicleId, date: timestamp.addingTimeInterval(2_000))
    let expense = makeExpense(vehicleId: vehicleId, date: timestamp.addingTimeInterval(1_000))
    let charge = makeCharge(vehicleId: vehicleId, date: timestamp.addingTimeInterval(3_000))
    try repo.upsertFillUp(fill)
    try repo.upsertExpense(expense)
    try repo.upsertChargeSession(charge)

    #expect(try repo.liveEntries(forVehicle: vehicleId).map(\.id) == [expense.id, fill.id, charge.id])

    try repo.softDeleteExpense(id: expense.id)
    #expect(try repo.liveEntries(forVehicle: vehicleId).map(\.id) == [fill.id, charge.id])
}
