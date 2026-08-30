import Foundation
import Testing
@testable import TankbookCore

// PJ.36 / PJ.38 - the export lanes (docs/TASKS.md rows 17):
//
// PJ.36: "Export everything" builds the WHOLE-ACCOUNT archive. The load-bearing
// test is the round-trip: the account archive decodes back through
// `VehicleArchiveReader` hash-equal to what the writer collected - blobs and
// all - so an export that silently drops anything is a diff, not a feeling.
//
// PJ.38: the per-car CSV export. Four tests pin what a CSV must never lose:
// per-type row counts (live + tombstoned, asserted per type, never as a total),
// the money PAIR (both amounts AND both currencies), a golden byte fixture (a
// column rename or date-format change is a visible diff), and the disk-full
// state (a surfaced message, never a crash - hard rule 7).
//
// The CSV fixture seed uses FIXED UUIDs and FIXED dates, so the golden bytes
// are reproducible across machines and runs.

// MARK: - Deterministic seed for the CSV fixture

enum CSVFixtureSeed {
    static let vehicle = UUID(uuidString: "00000000-0000-7000-8000-000000000101")!
    static let station1 = UUID(uuidString: "00000000-0000-7000-8000-000000000301")!
    static let station2 = UUID(uuidString: "00000000-0000-7000-8000-000000000302")!
    static let tariff = UUID(uuidString: "00000000-0000-7000-8000-000000000303")!
    static let fill1 = UUID(uuidString: "00000000-0000-7000-8000-000000000201")!
    static let fill2 = UUID(uuidString: "00000000-0000-7000-8000-000000000202")!
    static let charge = UUID(uuidString: "00000000-0000-7000-8000-000000000203")!
    static let service = UUID(uuidString: "00000000-0000-7000-8000-000000000204")!
    static let expense = UUID(uuidString: "00000000-0000-7000-8000-000000000205")!

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    static let units = Vehicle.Units(distance: .km, volume: .l,
                                     consumption: .lPer100, energy: .kWhPer100)

    /// Seeds one car with every entry type, a foreign-currency converted pair,
    /// a tombstoned fill and a station that is tombstoned too.
    static func seed(into repo: TankbookRepository) throws {
        try seedVehicleAndStations(into: repo)
        try seedFills(into: repo)
        try seedChargeAndServiceAndExpense(into: repo)
    }

    private static func seedVehicleAndStations(into repo: TankbookRepository) throws {
        try repo.upsertVehicle(Vehicle(
            id: vehicle, createdAt: date("2026-08-01T06:00:00Z"),
            updatedAt: date("2026-08-01T06:00:00Z"), deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2021, plate: "ABC-123",
            powertrain: .hybrid, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: .eur, units: units,
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 82_000))
        try repo.upsertStation(Station(
            id: station1, createdAt: date("2026-08-01T07:00:00Z"),
            updatedAt: date("2026-08-01T07:00:00Z"), deletedAt: nil,
            name: "Shell Tiergarten", brand: "Shell", location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: "V-Power"),
            lastUsedAt: date("2026-08-10T08:00:00Z")))
        try repo.upsertStation(Station(
            id: station2, createdAt: date("2026-08-01T07:00:00Z"),
            updatedAt: date("2026-08-01T07:00:00Z"), deletedAt: date("2026-08-12T07:00:00Z"),
            name: "Old Lukoil", brand: "Lukoil", location: nil, favorite: false,
            defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil), lastUsedAt: nil))
        try repo.upsertTariff(Tariff(
            id: tariff, createdAt: date("2026-08-01T07:00:00Z"),
            updatedAt: date("2026-08-01T07:00:00Z"), deletedAt: nil,
            vehicleId: vehicle, name: "Home wallbox", pricePerKWh: Decimal(string: "0.2395")!,
            currency: .eur, validFrom: date("2026-08-01T00:00:00Z")))
    }

    private static func seedFills(into repo: TankbookRepository) throws {
        // Live fill, converted pair, a note with a comma (quoting is pinned).
        try repo.upsertFillUp(FillUp(
            id: fill1, createdAt: date("2026-08-10T07:00:00Z"),
            updatedAt: date("2026-08-10T07:00:00Z"), deletedAt: nil,
            vehicleId: vehicle, date: date("2026-08-10T08:00:00Z"), odometer: 82_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: "Shell, A4 exit", attachments: [], provenance: .receiptScan,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 42.3, unitPrice: Decimal(string: "1.679")!, fuelKind: .petrol95,
            fuelGrade: "V-Power", isFull: true, tankLevelAfterPct: 100,
            stationId: station1, crossCheck: .verified, extraction: nil))
        // Tombstoned fill with a FOREIGN currency converted to home.
        let foreign = Money(amount: Decimal(string: "289.50")!, currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: Decimal(string: "4.2706")!,
                                           rateDate: date("2026-08-01T08:00:00Z"), source: .ecb))
        try repo.upsertFillUp(FillUp(
            id: fill2, createdAt: date("2026-08-01T06:00:00Z"),
            updatedAt: date("2026-08-01T06:00:00Z"), deletedAt: date("2026-08-12T08:00:00Z"),
            vehicleId: vehicle, date: date("2026-08-01T08:00:00Z"), odometer: 81_000,
            money: foreign, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 30.0, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: false, tankLevelAfterPct: 60, stationId: station2,
            crossCheck: .notApplicable, extraction: nil))
    }

    private static func seedChargeAndServiceAndExpense(into repo: TankbookRepository) throws {
        // Charge referencing the tariff.
        try repo.upsertChargeSession(ChargeSession(
            id: charge, createdAt: date("2026-08-11T07:00:00Z"),
            updatedAt: date("2026-08-11T07:00:00Z"), deletedAt: nil,
            vehicleId: vehicle, date: date("2026-08-11T08:00:00Z"), odometer: 82_400,
            money: Money(amount: Decimal(string: "6.63")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .fiscalQR, conflict: .none,
            purchaseGroupId: nil,
            energyKWh: 43.2, unitPrice: Decimal(string: "0.39")!, chargeType: .dcPublic,
            provider: "Ionity", tariffId: tariff, durationMin: 42,
            socStartPct: 18, socEndPct: 92, extraction: nil))
        try repo.upsertServiceRecord(ServiceRecord(
            id: service, createdAt: date("2026-08-05T07:00:00Z"),
            updatedAt: date("2026-08-05T07:00:00Z"), deletedAt: nil,
            vehicleId: vehicle, date: date("2026-08-05T08:00:00Z"), odometer: 82_500,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Bosch Service", items: [], usedParts: [],
            tireSetId: nil, proposedReminderId: nil))
        try repo.upsertExpense(Expense(
            id: expense, createdAt: date("2026-08-03T07:00:00Z"),
            updatedAt: date("2026-08-03T07:00:00Z"), deletedAt: nil,
            vehicleId: vehicle, date: date("2026-08-03T08:00:00Z"), odometer: nil,
            money: Money(amount: Decimal(string: "540.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .insurance, title: "Annual insurance",
            recurrence: nil, installedInServiceId: nil))
    }
}

// MARK: - Golden fixture helpers

private enum CSVFixture {
    static func directory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/export")
    }

    static func read(_ name: String) throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent(name))
    }
}

// MARK: - PJ.38: the golden fixture pins the CSV bytes

@Test func csvGoldenFixturesArePinnedByteForByte() throws {
    let repo = try ArchiveTest.makeRepo()
    try CSVFixtureSeed.seed(into: repo)
    let rendered = try CarCSVExport.render(vehicleID: CSVFixtureSeed.vehicle, repository: repo)

    for name in CarCSVExport.fileNames {
        let expected = try CSVFixture.read(name)
        let actual = Data(rendered[name]!.utf8)
        #expect(actual == expected,
                "\(name) drifted from its golden fixture - a column rename or a date-format change is a visible diff")
    }
}

// MARK: - PJ.38: row count = live + tombstoned entries, per type

@Test func csvRowCountsEqualLivePlusTombstonedEntriesPerType() throws {
    let repo = try ArchiveTest.makeRepo()
    try CSVFixtureSeed.seed(into: repo)
    let rendered = try CarCSVExport.render(vehicleID: CSVFixtureSeed.vehicle, repository: repo)

    // 1 live + 1 tombstoned fill = 2 data rows (header excluded).
    #expect(CarCSVExport.rowCount(of: rendered[CarCSVExport.fillUpsFile]!) == 2,
            "fill-ups must carry the live AND the tombstoned fill - a dropped tombstone loses data the user still owns")
    #expect(CarCSVExport.rowCount(of: rendered[CarCSVExport.chargeSessionsFile]!) == 1)
    #expect(CarCSVExport.rowCount(of: rendered[CarCSVExport.serviceFile]!) == 1)
    #expect(CarCSVExport.rowCount(of: rendered[CarCSVExport.expensesFile]!) == 1)

    // The tombstoned fill's row is identifiable by a non-empty deletedAt.
    let fillRows = CarCSVExport.dataRows(rendered[CarCSVExport.fillUpsFile]!)
    let tombstoned = fillRows.rows.first { $0["id"] == CSVFixtureSeed.fill2.uuidString.lowercased() }
    #expect(tombstoned != nil)
    #expect(tombstoned?["deletedAt"]?.isEmpty == false,
            "a tombstoned row must carry its deletedAt - that is what makes the count honest")
    let live = fillRows.rows.first { $0["id"] == CSVFixtureSeed.fill1.uuidString.lowercased() }
    #expect(live?["deletedAt"]?.isEmpty == true)
}

// MARK: - PJ.38: the money pair survives (hard rule 3)

@Test func csvMoneyPairSurvivesBothAmountsAndBothCurrencies() throws {
    let repo = try ArchiveTest.makeRepo()
    try CSVFixtureSeed.seed(into: repo)
    let rendered = try CarCSVExport.render(vehicleID: CSVFixtureSeed.vehicle, repository: repo)

    let rows = CarCSVExport.dataRows(rendered[CarCSVExport.fillUpsFile]!)
    let foreign = rows.rows.first { $0["id"] == CSVFixtureSeed.fill2.uuidString.lowercased() }!

    // The pair is NEVER one number: both amounts and both currencies ride.
    #expect(foreign["amount"] == "289.50", "the ORIGINAL amount must be present")
    #expect(foreign["currency"] == "PLN", "the ORIGINAL currency must be present")
    #expect(foreign["homeAmount"] == "67.79", "the HOME amount must be present")
    #expect(foreign["homeCurrency"] == "EUR", "the HOME currency must be present")
    #expect(foreign["rate"] == "4.2706", "the rate snapshot travels")
    #expect(foreign["rateDate"] == "2026-08-01", "the rate date = the entry date, never today")

    // A same-currency entry is the pair at rate 1.
    let live = rows.rows.first { $0["id"] == CSVFixtureSeed.fill1.uuidString.lowercased() }!
    #expect(live["amount"] == "71.02")
    #expect(live["currency"] == "EUR")
    #expect(live["homeAmount"] == "71.02")
    #expect(live["homeCurrency"] == "EUR")
}

// MARK: - PJ.36: the whole-account archive round-trips hash-equal

@Test func wholeAccountArchiveRoundTripsHashEqual() throws {
    let origin = try ArchiveTest.makeRepo()
    let seed = try ArchiveTest.seedGarage(into: origin)   // two-car garage, tombstones, blobs
    let archiveDir = try ArchiveTest.makeTempDir("account-archive")

    let writer = VehicleArchiveWriter(
        repository: origin,
        blobSource: FileBackedBlobSource(directory: seed.blobRoot))
    let manifest = try writer.writeAccountArchive(to: archiveDir)
    let collected = try writer.accountContents()

    // The manifest declares account scope - a vehicle import must refuse it.
    #expect(manifest.scope == .account)
    #expect(manifest.vehicleCount == 2)

    let target = try ArchiveTest.makeRepo()
    let blobStoreDir = try ArchiveTest.makeTempDir("account-blobstore")
    let reader = VehicleArchiveReader(repository: target,
                                      blobStore: FileBackedBlobStore(directory: blobStoreDir))
    let (decoded, stagedBlobs) = try reader.decodeContents(at: archiveDir)

    // Hash-equal: every vehicle, entry, reminder, station, tariff, attachment
    // and blob byte the writer collected is what the reader decodes back.
    #expect(decoded == collected,
            "the account archive must round-trip hash-equal - a dropped row or blob is a deletion that comes back")
    #expect(stagedBlobs == collected.blobs, "the blob bytes must survive byte-for-byte")

    // And the local importer still refuses an account archive (P5.5a's guard).
    do {
        _ = try reader.importArchive(at: archiveDir, mode: .singleCar)
        Issue.record("a whole-account archive is not a car; a single-car import must refuse it")
    } catch let error as VehicleArchiveError {
        #expect(error == .scopeMismatch(expected: .singleCar, declared: .account))
    }
    #expect(try target.liveVehicles().isEmpty, "the refused import wrote nothing")
}

// MARK: - PJ.36/PJ.38: disk-full is a surfaced message, never a crash

@Test func diskFullFailureSurfacesItsMessageNotACrash() throws {
    let diskFull = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                           userInfo: [NSFilePathErrorKey: "/var/mobile/.../manifest.json"])
    let failure = ExportFailure.map(diskFull)
    #expect(failure == .insufficientStorage,
            "a disk-full write error must classify as insufficient storage - the surfaced state, not a crash")
    #expect(failure.defaultMessage == "Not enough space to build the export.")

    // An unrelated failure stays generic and still surfaces a message.
    let other = ExportFailure.map(NSError(domain: "com.example", code: 7))
    #expect(other == .underlying)
    #expect(other.defaultMessage == "Couldn't build the export.")
}
