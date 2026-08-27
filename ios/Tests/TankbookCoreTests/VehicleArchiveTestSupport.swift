import Foundation
import Testing
@testable import TankbookCore

// P5.5a test scaffolding (shared with VehicleArchiveTests.swift), namespaced
// under `ArchiveTest` so it cannot collide with the same-named private helpers
// other test files already declare. Everything here uses REAL temp directories
// for the archive, the blob source and the blob store: the atomic write and the
// content-addressed bytes are part of what is under test, not something to mock
// away.

enum ArchiveTest {
    static let time0 = Date(timeIntervalSinceReferenceDate: 0)
    static let time1 = time0.addingTimeInterval(86_400)
    static let time2 = time0.addingTimeInterval(2 * 86_400)
    static let time3 = time0.addingTimeInterval(3 * 86_400)

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    // MARK: - Test scaffolding (real temp directories)

    static func makeTempDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tankbook-archive-tests/\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeRepo() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    /// Writes a real blob file where `FileBackedBlobSource` will look, and
    /// returns the content address the Attachment must carry.
    @discardableResult
    static func writeBlobFile(in root: URL, relativePath: String, bytes: Data) throws -> String {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
        return BlobHash.sha256(bytes)
    }

    // MARK: - A two-car garage seed

    /// The ids of every row in the seeded garage, so tests assert on specific
    /// rows rather than counts.
    struct GarageSeed {
        var volvo = UUID.v7()
        var tesla = UUID.v7()

        var stationLive = UUID.v7()
        var stationDeleted = UUID.v7()

        var tariffVehicle = UUID.v7()
        var tariffShared = UUID.v7()

        var attachmentLive = UUID.v7()
        var attachmentDeleted = UUID.v7()
        var attachmentPhoto = UUID.v7()
        var shaLive: String
        var shaDeleted: String
        var shaPhoto: String

        var fillLive = UUID.v7()
        var fillDeleted = UUID.v7()
        var chargeLive = UUID.v7()
        var serviceLive = UUID.v7()
        var expenseLive = UUID.v7()
        var reminderLive = UUID.v7()
        var reminderDeleted = UUID.v7()
        var teslaFill = UUID.v7()
        /// Where the seed's blob FILES physically live - the export must read
        /// the same directory, so the round-trip exercises real bytes end to end.
        var blobRoot: URL

        init(blobRoot: URL) throws {
            self.blobRoot = blobRoot
            shaLive = try writeBlobFile(in: blobRoot, relativePath: "photos/2026/07/seed.jpg",
                                        bytes: Data("JPEG-CONTENT-LIVE".utf8))
            shaDeleted = try writeBlobFile(in: blobRoot, relativePath: "photos/2026/07/deleted.jpg",
                                           bytes: Data("JPEG-CONTENT-DELETED".utf8))
            shaPhoto = try writeBlobFile(in: blobRoot, relativePath: "photos/2026/07/photo.jpg",
                                         bytes: Data("JPEG-CONTENT-PHOTO".utf8))
        }
    }

    static func makeVolvo(_ id: UUID) -> Vehicle {
        Vehicle(
            id: id, createdAt: time0, updatedAt: time0, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2021, plate: "ABC-123",
            powertrain: .hybrid, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 82_000)
    }

    static func makeTesla(_ id: UUID) -> Vehicle {
        Vehicle(
            id: id, createdAt: time0, updatedAt: time0, deletedAt: nil,
            name: "Tesla Model Y", make: "Tesla", model: "Model Y", year: 2024, plate: "EV-999",
            powertrain: .ev, fuelKinds: [.electricity], tankCapacityL: nil,
            batteryCapacityKWh: 75, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 12_000)
    }

    /// Seeds a two-car garage (Volvo + Tesla) into `repo`, with every entry
    /// type, referenced stations/tariffs/attachments, and deliberate tombstones.
    /// Returns the seed so tests can assert on rows, not totals.
    @discardableResult
    static func seedGarage(into repo: TankbookRepository) throws -> GarageSeed {
        let blobRoot = try makeTempDir("seed-blobs")
        let seed = try GarageSeed(blobRoot: blobRoot)

        // ---- Volvo: the exported car
        var volvo = makeVolvo(seed.volvo)
        volvo.photo = seed.attachmentPhoto
        try repo.upsertVehicle(volvo)

        try repo.upsertStation(Station(
            id: seed.stationLive, createdAt: time0, updatedAt: time0, deletedAt: nil,
            name: "Shell Tiergarten", brand: "Shell",
            location: GeoCoordinate(latitude: 52.51, longitude: 13.35), favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: "V-Power"), lastUsedAt: time1))
        try repo.upsertStation(Station(
            id: seed.stationDeleted, createdAt: time0, updatedAt: time0, deletedAt: time2,
            name: "Old Lukoil", brand: "Lukoil", location: nil, favorite: false,
            defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil), lastUsedAt: nil))

        try repo.upsertTariff(Tariff(
            id: seed.tariffVehicle, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.volvo, name: "Home wallbox", pricePerKWh: decimal("0.2395"),
            currency: .eur, validFrom: time0))
        try repo.upsertTariff(Tariff(
            id: seed.tariffShared, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: nil, name: "Household night rate", pricePerKWh: decimal("0.19"),
            currency: .eur, validFrom: time0))

        var liveAttachment = makeSyncAttachment(id: seed.attachmentLive, sha256: seed.shaLive,
                                                relativePath: "photos/2026/07/seed.jpg")
        var deletedAttachment = makeSyncAttachment(id: seed.attachmentDeleted, sha256: seed.shaDeleted,
                                                   relativePath: "photos/2026/07/deleted.jpg")
        deletedAttachment.deletedAt = time2
        let photoAttachment = makeSyncAttachment(id: seed.attachmentPhoto, sha256: seed.shaPhoto,
                                                 relativePath: "photos/2026/07/photo.jpg")
        try repo.upsertAttachment(liveAttachment)
        try repo.upsertAttachment(deletedAttachment)
        try repo.upsertAttachment(photoAttachment)

        try seedVolvoFillsAndCharges(into: repo, seed: seed)
        try seedVolvoService(into: repo, seed: seed)
        try seedVolvoExpenseAndReminder(into: repo, seed: seed)
        try seedVolvoDeletedReminder(into: repo, seed: seed)
        try seedVolvoReminders(into: repo, seed: seed)

        // ---- Tesla: the OTHER car, which must never appear in Volvo's archive
        try seedTesla(into: repo, seed: seed)
        return seed
    }

    /// Volvo's fuel and charge history - the live fill, a tombstoned fill, and
    /// a charge that references the shared tariff.
    private static func seedVolvoFillsAndCharges(into repo: TankbookRepository, seed: GarageSeed) throws {
        try repo.upsertFillUp(FillUp(
            id: seed.fillLive, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.volvo, date: time1, odometer: 82_000,
            money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
            note: "Shell, A4 exit", attachments: [seed.attachmentLive],
            provenance: .receiptScan, conflict: .none, purchaseGroupId: nil,
            volumeL: 42.3, unitPrice: decimal("1.679"), fuelKind: .petrol95,
            fuelGrade: "V-Power", isFull: true, tankLevelAfterPct: 100, stationId: seed.stationLive,
            crossCheck: .verified, extraction: nil))
        try repo.upsertFillUp(FillUp(
            id: seed.fillDeleted, createdAt: time0, updatedAt: time0, deletedAt: time2,
            vehicleId: seed.volvo, date: time0, odometer: 81_900,
            money: nil, note: nil, attachments: [seed.attachmentDeleted],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            volumeL: 30.0, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: false, tankLevelAfterPct: 60, stationId: seed.stationDeleted,
            crossCheck: .notApplicable, extraction: nil))
        try repo.upsertChargeSession(ChargeSession(
            id: seed.chargeLive, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.volvo, date: time2, odometer: 82_400,
            money: Money(amount: decimal("6.63"), currency: .eur, homeCurrency: .eur),
            note: "Ionity stop", attachments: [seed.attachmentLive],
            provenance: .fiscalQR, conflict: .none, purchaseGroupId: nil,
            energyKWh: 43.2, unitPrice: decimal("0.39"), chargeType: .dcPublic,
            provider: "Ionity", tariffId: seed.tariffShared, durationMin: 42,
            socStartPct: 18, socEndPct: 92, extraction: nil))
    }

    private static func seedVolvoService(into repo: TankbookRepository, seed: GarageSeed) throws {
        try repo.upsertServiceRecord(ServiceRecord(
            id: seed.serviceLive, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.volvo, date: time3, odometer: 82_500,
            money: Money(amount: decimal("148.00"), currency: .eur, homeCurrency: .eur),
            note: "Annual service", attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            vendor: "Bosch Service",
            items: [
                ServiceItem(title: "Engine oil", category: .oil,
                            cost: Money(amount: decimal("89.00"), currency: .eur, homeCurrency: .eur),
                            partNumber: "MANN W 712/75",
                            lifetime: ServiceItem.Lifetime(km: 15_000, months: 12)),
                ServiceItem(title: "Cabin filter", category: .filters,
                            cost: nil, partNumber: nil, lifetime: nil)
            ],
            usedParts: [], tireSetId: nil, proposedReminderId: nil))
    }

    private static func seedVolvoExpenseAndReminder(into repo: TankbookRepository, seed: GarageSeed) throws {
        try repo.upsertExpense(Expense(
            id: seed.expenseLive, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.volvo, date: time1, odometer: nil,
            money: Money(amount: decimal("540.00"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
            category: .insurance, title: "Annual insurance",
            recurrence: RecurrenceRule(everyMonths: 12, anchorDate: time0), installedInServiceId: nil))
    }

    private static func seedVolvoReminders(into repo: TankbookRepository, seed: GarageSeed) throws {
        try repo.upsertReminder(Reminder(
            id: seed.reminderLive, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.volvo, title: "Oil change", category: .oil,
            dueDate: time3, dueOdometer: 90_000,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: nil),
            sourceEntryId: nil, status: .scheduled))
    }

    private static func seedVolvoDeletedReminder(into repo: TankbookRepository, seed: GarageSeed) throws {
        try repo.upsertReminder(Reminder(
            id: seed.reminderDeleted, createdAt: time0, updatedAt: time0, deletedAt: time2,
            vehicleId: seed.volvo, title: "Winter tires", category: .tires,
            dueDate: nil, dueOdometer: nil, recurrence: nil, sourceEntryId: nil,
            status: .dismissed(reason: "Switched provider")))
    }

    private static func seedTesla(into repo: TankbookRepository, seed: GarageSeed) throws {
        try repo.upsertVehicle(makeTesla(seed.tesla))
        try repo.upsertFillUp(FillUp(
            id: seed.teslaFill, createdAt: time0, updatedAt: time0, deletedAt: nil,
            vehicleId: seed.tesla, date: time1, odometer: 12_000,
            money: Money(amount: decimal("12.40"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
            volumeL: 62.5, unitPrice: decimal("0.19"), fuelKind: .electricity, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil))
    }

    // MARK: - Export / import helpers

    static func exportVolvo(from repo: TankbookRepository, vehicleID: UUID,
                            to directory: URL, blobSourceDir: URL,
                            passphrase: String? = nil,
                            policy: ArchiveSchemaPolicy = .current,
                            now: Date = time0) throws -> VehicleArchiveManifest {
        let writer = VehicleArchiveWriter(repository: repo,
                                          blobSource: FileBackedBlobSource(directory: blobSourceDir),
                                          policy: policy)
        return try writer.writeArchive(
            vehicleID: vehicleID, to: directory, appVersion: "9.9.9", passphrase: passphrase,
            kdfIterations: ArchiveCrypto.testIterations, now: now)
    }

    static func importArchive(_ directory: URL, into repo: TankbookRepository,
                              blobStoreDir: URL,
                              mode: VehicleArchiveImportMode = .singleCar,
                              passphrase: String? = nil,
                              policy: ArchiveSchemaPolicy = .current) throws -> VehicleArchiveImportResult {
        let reader = VehicleArchiveReader(repository: repo,
                                          blobStore: FileBackedBlobStore(directory: blobStoreDir),
                                          policy: policy)
        return try reader.importArchive(at: directory, mode: mode, passphrase: passphrase,
                                        kdfIterations: ArchiveCrypto.testIterations)
    }

    /// The empty-state assertion every "rejected whole" test ends with: the
    /// repository is byte-for-byte untouched (no rows in ANY synced table, plus
    /// the two device-local bookkeeping tables) and the blob store has no bytes.
    static func assertRepositoryEmpty(_ repo: TankbookRepository, blobStoreDir: URL) throws {
        for table in TankbookSchema.syncedTables {
            #expect(try repo.rowCount(in: table) == 0, "\(table) must be untouched after a rejected import")
        }
        #expect(try repo.rowCount(in: TankbookSchema.syncOverwrite) == 0)
        let blobs = try FileManager.default.contentsOfDirectory(at: blobStoreDir, includingPropertiesForKeys: nil)
        #expect(blobs.isEmpty, "a rejected import must leave no blob bytes behind")
    }
}
