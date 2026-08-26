import Foundation
import Testing
@testable import TankbookCore

/// P4.11: `Date` must round-trip exactly through persistence. Dates are stored
/// as `timeIntervalSinceReferenceDate` - the same Double `Date` itself holds -
/// so a record read straight back after a write is exactly the record written:
/// no epoch offset, no normalization, no tolerance. Every fixture here uses a
/// sub-second date on purpose; a whole-second fixture would pass under either
/// storage format and prove nothing.
@Suite struct DateRoundTripTests {

    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000.123456)

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle(id: UUID = UUID.v7()) -> Vehicle {
        Vehicle(
            id: id,
            createdAt: base,
            updatedAt: base.addingTimeInterval(1.5),
            deletedAt: nil,
            name: "Volvo V60",
            make: "Volvo",
            model: "V60",
            year: 2015,
            plate: nil,
            powertrain: .ice,
            fuelKinds: [.petrol95],
            tankCapacityL: 71,
            batteryCapacityKWh: nil,
            homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil,
            archived: false,
            paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
    }

    // MARK: - Whole-record equality, every entity type (L1)

    @Test func fillUpRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeVehicle(id: vehicleId))
        let fillUp = FillUp(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, date: base.addingTimeInterval(2.25), odometer: 82_400,
            money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
            note: "Shell, A4 exit", attachments: [UUID.v7()],
            provenance: .receiptScan, conflict: .none, purchaseGroupId: UUID.v7(),
            volumeL: 42.3, unitPrice: decimal("1.679"), fuelKind: .petrol95, fuelGrade: "V-Power",
            isFull: true, tankLevelAfterPct: 100, stationId: UUID.v7(),
            crossCheck: .verified, extraction: nil)
        try repo.upsertFillUp(fillUp)
        #expect(try repo.liveFillUps(forVehicle: vehicleId) == [fillUp])
    }

    @Test func chargeSessionRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeVehicle(id: vehicleId))
        let charge = ChargeSession(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, date: base.addingTimeInterval(2.25), odometer: 18_000,
            money: Money(amount: decimal("6.63"), currency: .eur, homeCurrency: .eur),
            note: "Ionity stop", attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil,
            energyKWh: 43.2, unitPrice: decimal("0.39"), chargeType: .dcPublic,
            provider: "Ionity", tariffId: nil, durationMin: 42, socStartPct: 18, socEndPct: 92,
            extraction: nil)
        try repo.upsertChargeSession(charge)
        #expect(try repo.liveChargeSessions(forVehicle: vehicleId) == [charge])
    }

    @Test func serviceRecordRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeVehicle(id: vehicleId))
        let service = ServiceRecord(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, date: base.addingTimeInterval(2.25), odometer: 90_000,
            money: nil, note: "Annual service", attachments: [UUID.v7()],
            provenance: .manual, conflict: .none, purchaseGroupId: UUID.v7(),
            vendor: "Bosch Service",
            items: [
                ServiceItem(title: "Oil change", category: .oil,
                            cost: Money(amount: decimal("89.00"), currency: .eur, homeCurrency: .eur),
                            partNumber: "MANN W 712/75",
                            lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
            ],
            usedParts: [UUID.v7()], tireSetId: nil, proposedReminderId: UUID.v7())
        try repo.upsertServiceRecord(service)
        #expect(try repo.liveServiceRecords(forVehicle: vehicleId) == [service])
    }

    @Test func expenseRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeVehicle(id: vehicleId))
        let expense = Expense(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, date: base.addingTimeInterval(2.25), odometer: nil,
            money: Money(amount: decimal("540.00"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
            category: .insurance, title: "Annual insurance", recurrence: nil,
            installedInServiceId: nil)
        try repo.upsertExpense(expense)
        #expect(try repo.liveExpenses(forVehicle: vehicleId) == [expense])
    }

    @Test func vehicleRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)
        #expect(try repo.liveVehicles() == [vehicle])
        #expect(try repo.vehicle(id: vehicle.id) == vehicle)
    }

    @Test func reminderRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeVehicle(id: vehicleId))
        let reminder = Reminder(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, title: "Oil change", category: .oil,
            dueDate: base.addingTimeInterval(3.25), dueOdometer: 105_000,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12),
            sourceEntryId: UUID.v7(), status: .scheduled)
        try repo.upsertReminder(reminder)
        #expect(try repo.liveReminders(forVehicle: vehicleId) == [reminder])
    }

    @Test func tireSetRoundTripsExactly() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()
        try repo.upsertVehicle(makeVehicle(id: vehicleId))
        let tireSet = TireSet(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, name: "Winter Nokian", purchaseExpenseId: UUID.v7())
        try repo.upsertTireSet(tireSet)
        #expect(try repo.liveTireSets(forVehicle: vehicleId) == [tireSet])
    }

    @Test func attachmentRoundTripsExactly() throws {
        let repo = try makeRepository()
        let attachment = Attachment(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            kind: .pdf,
            file: LocalFileRef(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                               relativePath: "pdfs/2026/07/9f86d081.pdf"),
            extractedTimestamp: nil, ocrText: "SHELL 71.02 42.30 1.679")
        try repo.upsertAttachment(attachment)
        #expect(try repo.liveAttachments() == [attachment])
    }

    // MARK: - Sub-second precision survives (L1)

    @Test func subSecondPrecisionSurvivesExactly() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let readBack = try repo.vehicle(id: vehicle.id)!
        // Asserted as equality, not abs(a - b) < x - the whole point of P4.11.
        #expect(readBack.createdAt == base)
        #expect(readBack.updatedAt == base.addingTimeInterval(1.5))
        #expect(readBack.createdAt == vehicle.createdAt)
        #expect(readBack.updatedAt == vehicle.updatedAt)
    }

    // MARK: - The v3 migration (L1)

    @Test func migrationConvertsOldEpochDatesToReferenceDate() throws {
        let seed = try seedOldFormatDatabase()

        // Apply the forward migrations over the seeded rows.
        try seed.database.migrator.migrate(seed.database.writer)

        let repo = TankbookRepository(database: seed.database)
        let vehicle = try repo.vehicle(id: seed.vehicleID)
        #expect(vehicle != nil)
        #expect(equalToTheSecond(vehicle!.createdAt, seed.createdAt))
        #expect(equalToTheSecond(vehicle!.updatedAt, seed.updatedAt))
        #expect(vehicle!.deletedAt != nil)
        #expect(equalToTheSecond(vehicle!.deletedAt!, seed.deletedAt))
        #expect(equalToTheSecond(vehicle!.archivedAt!, seed.archivedAt))

        let fills = try repo.liveFillUps(forVehicle: seed.vehicleID)
        #expect(fills.count == 1)
        #expect(equalToTheSecond(fills[0].date, seed.entryDate))
        #expect(equalToTheSecond(fills[0].money!.rateDate!, seed.rateDate))

        let attachments = try repo.liveAttachments()
        #expect(attachments.count == 1)
        #expect(equalToTheSecond(attachments[0].extractedTimestamp!, seed.extractedTimestamp))
    }

    /// A database seeded in the OLD format (v2, epoch-1970 seconds) with
    /// fractional dates, plus the originals for the assertions.
    private struct OldFormatSeed {
        let database: TankbookDatabase
        let vehicleID: UUID
        let fillUpID: UUID
        let attachmentID: UUID
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date
        let archivedAt: Date
        let entryDate: Date
        let rateDate: Date
        let extractedTimestamp: Date
    }

    private func seedOldFormatDatabase() throws -> OldFormatSeed {
        let database = try TankbookDatabase.inMemory(upTo: "v2")
        let vehicleID = UUID.v7()
        let fillUpID = UUID.v7()
        let attachmentID = UUID.v7()
        let createdAt = base
        let updatedAt = base.addingTimeInterval(1.5)
        let deletedAt = base.addingTimeInterval(2.25)
        let archivedAt = base.addingTimeInterval(3.75)
        let entryDate = base.addingTimeInterval(4.5)
        let rateDate = base.addingTimeInterval(5.25)
        let extractedTimestamp = base.addingTimeInterval(6.75)

        try database.write { db in
            try db.execute(sql: """
                INSERT INTO vehicle (id, createdAt, updatedAt, deletedAt, archivedAt, name,
                    powertrain, fuelKinds, homeCurrency, distanceUnit, volumeUnit,
                    consumptionUnit, energyUnit)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    vehicleID.uuidString,
                    createdAt.timeIntervalSince1970,
                    updatedAt.timeIntervalSince1970,
                    deletedAt.timeIntervalSince1970,
                    archivedAt.timeIntervalSince1970,
                    "Volvo", "ice", #"["petrol95"]"#, "eur", "km", "l", "lPer100", "kWhPer100"
                ])
            try db.execute(sql: """
                INSERT INTO fillUp (id, createdAt, updatedAt, vehicleId, date, amount, currency,
                    homeAmount, homeCurrency, rate, rateDate, rateSource, provenance, conflict,
                    crossCheck, volumeL, fuelKind)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    fillUpID.uuidString,
                    createdAt.timeIntervalSince1970,
                    updatedAt.timeIntervalSince1970,
                    vehicleID.uuidString,
                    entryDate.timeIntervalSince1970,
                    "289.50", "pln", "67.79", "eur", "4.2706",
                    rateDate.timeIntervalSince1970, "ecb",
                    #"{"tag":"manual"}"#, #"{"tag":"none"}"#,
                    #"{"tag":"verified"}"#, 42.3, "petrol95"
                ])
            try db.execute(sql: """
                INSERT INTO attachment (id, createdAt, updatedAt, extractedTimestamp, kind,
                    fileSha256, fileRelativePath)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    attachmentID.uuidString,
                    createdAt.timeIntervalSince1970,
                    updatedAt.timeIntervalSince1970,
                    extractedTimestamp.timeIntervalSince1970,
                    "photo", "deadbeef", "img/deadbeef.jpg"
                ])
        }

        return OldFormatSeed(
            database: database, vehicleID: vehicleID, fillUpID: fillUpID, attachmentID: attachmentID,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            archivedAt: archivedAt, entryDate: entryDate, rateDate: rateDate,
            extractedTimestamp: extractedTimestamp)
    }

    @Test func migrationDoesNotShiftValuesOnReapply() throws {
        // A double conversion is 31 years off and must be impossible: GRDB
        // records v3 as applied, so running the migrator again is a no-op and
        // the stored date does not shift a second time.
        let database = try TankbookDatabase.inMemory(upTo: "v2")
        let vehicleID = UUID.v7()
        let createdAt = base

        try database.write { db in
            try db.execute(sql: """
                INSERT INTO vehicle (id, createdAt, updatedAt, name, powertrain, fuelKinds,
                    homeCurrency, distanceUnit, volumeUnit, consumptionUnit, energyUnit)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    vehicleID.uuidString, createdAt.timeIntervalSince1970,
                    createdAt.timeIntervalSince1970, "Volvo", "ice", #"["petrol95"]"#,
                    "eur", "km", "l", "lPer100", "kWhPer100"
                ])
        }

        try database.migrator.migrate(database.writer)
        let repo = TankbookRepository(database: database)
        let firstRead = try repo.vehicle(id: vehicleID)!.createdAt

        try database.migrator.migrate(database.writer)
        let secondRead = try repo.vehicle(id: vehicleID)!.createdAt

        #expect(secondRead == firstRead, "a re-applied migration must not shift the date again")
        #expect(equalToTheSecond(secondRead, createdAt))
    }

    // MARK: - Every date column (L1)

    @Test func forgottenDateColumnsSurviveIntact() throws {
        let repo = try makeRepository()
        let vehicleId = UUID.v7()

        // deletedAt + archivedAt on a vehicle, read back by id (no live filter).
        var vehicle = makeVehicle(id: vehicleId)
        vehicle.archived = true
        vehicle.archivedAt = base.addingTimeInterval(10.5)
        vehicle.deletedAt = base.addingTimeInterval(11.25)
        try repo.upsertVehicle(vehicle)
        #expect(try repo.vehicle(id: vehicleId) == vehicle)

        // rateDate on a cross-currency fill-up (a full Money snapshot pair).
        let fill = FillUp(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            vehicleId: vehicleId, date: base.addingTimeInterval(12.25), odometer: 82_400,
            money: Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
                .converted(using: RateSnapshot(rate: decimal("4.2706"),
                                               rateDate: base.addingTimeInterval(13.5),
                                               source: .ecb)),
            note: nil, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
            volumeL: 42.3, unitPrice: decimal("6.85"), fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
        try repo.upsertFillUp(fill)
        #expect(try repo.liveFillUps(forVehicle: vehicleId) == [fill])

        // extractedTimestamp on an attachment.
        let attachment = Attachment(
            id: UUID.v7(), createdAt: base, updatedAt: base.addingTimeInterval(1.5), deletedAt: nil,
            kind: .photo,
            file: LocalFileRef(sha256: "deadbeef", relativePath: "img/deadbeef.jpg"),
            extractedTimestamp: base.addingTimeInterval(14.75), ocrText: nil)
        try repo.upsertAttachment(attachment)
        #expect(try repo.liveAttachments() == [attachment])
    }

    // MARK: - Helpers

    /// Whole-second equality (the migration's contract is "equal to the
    /// original to the second", because the old epoch-1970 rows already carried
    /// the one-ulp drift baked in). Compared by second, not by tolerance.
    private func equalToTheSecond(_ lhs: Date, _ rhs: Date) -> Bool {
        Int(lhs.timeIntervalSinceReferenceDate) == Int(rhs.timeIntervalSinceReferenceDate)
    }
}
