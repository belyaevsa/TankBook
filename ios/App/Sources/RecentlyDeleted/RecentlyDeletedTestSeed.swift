import Foundation
import TankbookCore

#if DEBUG
/// UI-test seeding for the Recently deleted screen (P1.7), the same pattern as
/// `HomeTestSeed` and `HomePresentables`.
///
/// The screen's real data is tombstones:
/// - `-seedRecentlyDeleted` writes a vehicle and three entries (a fill, a
///   charge, an expense) tombstoned individually at ages that reproduce the
///   artboard's countdowns (27/19/4 days left on the run date), so the UI
///   tests and screenshots match design/screens/RecentlyDeleted.dc.html.
/// - `-seedRecentlyDeletedVehicle` (RV.98) writes a car tombstoned with four
///   fills at the same stamp (ONE car row, never a flood of fills) plus an
///   expense and a reminder tombstoned individually BEFORE it (their own rows,
///   left alone by the car's Restore).
///
/// - `-forceSyncOverwritten` writes a REAL `syncOverwrite` log row - the same
///   record a merge writes (docs/SYNC.md S1/S4) - so the "Overwritten by sync"
///   section is exercised from data, never from a render-time flag.
/// - `-forceRemovedElsewhere` annotates the seeded charge as "removed on
///   iPad" - still a fixture: v1 carries no per-device tombstone attribution
///   (docs/ERRORS.md -> Recently deleted).
enum RecentlyDeletedTestSeed {
    /// Entry ids that sync says were deleted on another device. Populated by
    /// the seed under `-forceRemovedElsewhere`; empty in production - v1 carries
    /// no per-device tombstone attribution (docs/ERRORS.md -> Recently deleted).
    /// `nonisolated(unsafe)` because it is fixture bookkeeping written and read
    /// on the main actor only (the view reads it while the seed is MainActor).
    nonisolated(unsafe) static var removedElsewhereIDs: Set<UUID> = []

    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let vehicleSeed = arguments.contains("-seedRecentlyDeletedVehicle")
        let entrySeed = arguments.contains("-seedRecentlyDeleted")
        let shouldReset = arguments.contains("-homeResetDatabase")
        guard vehicleSeed || entrySeed || shouldReset else { return }

        if shouldReset {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        // Idempotent (same contract as HomeTestSeed): a run that already
        // seeded - or another suite's seed - is left alone.
        guard vehicleSeed || entrySeed,
              (try? repository.liveVehicles())?.isEmpty != false else { return }

        if entrySeed {
            seed(repository)
        }
        if vehicleSeed {
            seedVehicle(repository)
        }
        if arguments.contains("-forceSyncOverwritten") {
            seedSyncOverwrite(repository)
        }

        if arguments.contains("-forceRemovedElsewhere") {
            // This device's own tombstones are indistinguishable from ones
            // received via sync (the row knows only `deletedAt`); the fixture
            // chooses the seeded charge row, matching the artboard.
            removedElsewhereIDs = Set(tombstonedChargeIDs(in: repository))
        }
    }

    // MARK: - Seed

    /// The artboard's three rows: a Neste fill (27 days left), an Ionity
    /// charge (19 days left) and a Car wash expense (4 days left on the run
    /// date - the artboard's 5 when it was drawn a day earlier).
    private static func seed(_ repository: TankbookRepository) {
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
        try? repository.upsertVehicle(vehicle)

        let neste = makeStation(repository, name: "Neste")
        let fill = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now.addingTimeInterval(-3 * 86_400),
            odometer: 121_900, money: Money(amount: Decimal(string: "84.77")!,
                                             currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 51.1, unitPrice: Decimal(string: "1.659")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: 100, stationId: neste.id,
            crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(fill)
        try? repository.softDeleteFillUp(id: fill.id, at: now.addingTimeInterval(-3 * 86_400))

        let charge = ChargeSession(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now.addingTimeInterval(-11 * 86_400),
            odometer: 121_200, money: Money(amount: Decimal(string: "14.10")!,
                                             currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            energyKWh: 24, unitPrice: nil, chargeType: .dcPublic,
            provider: "Ionity", tariffId: nil, durationMin: 31,
            socStartPct: 18, socEndPct: 82, extraction: nil)
        try? repository.upsertChargeSession(charge)
        try? repository.softDeleteChargeSession(id: charge.id, at: now.addingTimeInterval(-11 * 86_400))

        let expense = Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now.addingTimeInterval(-26 * 86_400),
            odometer: nil, money: Money(amount: Decimal(string: "12.00")!,
                                        currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            category: .other("car wash"), title: "Car wash",
            installedInServiceId: nil)
        try? repository.upsertExpense(expense)
        try? repository.softDeleteExpense(id: expense.id, at: now.addingTimeInterval(-26 * 86_400))

        // PJ.7: a tombstoned reminder joins the entry tombstones - hard rule 8
        // holds for reminders too. Deleted 6 days ago, so its countdown reads
        // "24 days left" on any run date, distinct from the entries' three.
        let reminder = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Oil change", category: .oil,
            dueDate: now.addingTimeInterval(30 * 86_400), dueOdometer: nil,
            recurrence: Reminder.Recurrence(everyKm: 15_000, everyMonths: 12))
        try? repository.upsertReminder(reminder)
        try? repository.softDeleteReminder(id: reminder.id, at: now.addingTimeInterval(-6 * 86_400))
    }

    // MARK: - RV.98: a deleted car is one row on Recently deleted

    /// The RV.98 state: a car deleted 3 days ago with four live entries that
    /// went down with it at the same stamp - so the screen shows ONE car row
    /// ("Volvo V60 and 4 entries", 27 days left), never the four fills beside
    /// it with Restores of their own. An expense deleted individually five days
    /// earlier (its own stamp) and a reminder deleted six days earlier still
    /// list as their own rows exactly as before - restoring the car restores
    /// the group and leaves those two tombstones alone.
    private static func seedVehicle(_ repository: TankbookRepository) {
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
        try? repository.upsertVehicle(vehicle)

        let nesta = makeStation(repository, name: "Neste")
        for spec in [
            HomeTestSeed.FillSpec(daysAgo: 40, odometer: 118_600, litres: 42.1,
                                  amount: "70.56", price: "1.676", stationID: nesta.id),
            HomeTestSeed.FillSpec(daysAgo: 30, odometer: 119_400, litres: 41.4,
                                  amount: "69.14", price: "1.670", stationID: nesta.id),
            HomeTestSeed.FillSpec(daysAgo: 20, odometer: 120_200, litres: 43.0,
                                  amount: "71.17", price: "1.655", stationID: nesta.id),
            HomeTestSeed.FillSpec(daysAgo: 10, odometer: 121_000, litres: 40.6,
                                  amount: "66.18", price: "1.630", stationID: nesta.id)
        ] {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: vehicle.id, spec))
        }

        // Individually deleted BEFORE the car went: these two keep their own
        // stamps and must stay their own rows after the car's Restore.
        let wash = Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now.addingTimeInterval(-6 * 86_400),
            odometer: nil, money: Money(amount: Decimal(string: "12.00")!,
                                        currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            category: .other("car wash"), title: "Car wash",
            installedInServiceId: nil)
        try? repository.upsertExpense(wash)
        try? repository.softDeleteExpense(id: wash.id, at: now.addingTimeInterval(-5 * 86_400))

        let reminder = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Oil change", category: .oil,
            dueDate: now.addingTimeInterval(30 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(reminder)
        try? repository.softDeleteReminder(id: reminder.id, at: now.addingTimeInterval(-6 * 86_400))

        // The car goes 3 days ago: the four live fills share its stamp and
        // become the car row's covered group.
        try? repository.softDeleteVehicle(id: vehicle.id, at: now.addingTimeInterval(-3 * 86_400))
    }

    // MARK: - The real "Overwritten by sync" log row

    /// The real undo-log row the section reads: a live Neste fill whose user
    /// version (a different odometer) lost to a sync merge, attributed to the
    /// iPad. Written through `recordSyncOverwrite`, the call `SyncEngine` makes,
    /// so the section is exercised from the log, not from a render-time flag.
    private static func seedSyncOverwrite(_ repository: TankbookRepository) {
        guard let vehicle = (try? repository.liveVehicles())?.first else { return }
        let now = Date()
        let station = (try? repository.liveStations())?.first { $0.name == "Neste" }
        let target = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now.addingTimeInterval(-2 * 86_400),
            odometer: 121_500, money: Money(amount: Decimal(string: "86.10")!,
                                            currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 51.8, unitPrice: Decimal(string: "1.662")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: station?.id, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(target, syncState: .synced(scn: 1))
        guard (try? repository.syncOverwrite(for: target.id)) == nil else { return }

        // The user's own version - the same fill with their odometer 121 400.
        let userVersion = FillUp(
            id: target.id, createdAt: target.createdAt, updatedAt: target.updatedAt,
            deletedAt: nil, vehicleId: target.vehicleId, date: target.date,
            odometer: 121_400, money: target.money, note: target.note,
            attachments: target.attachments, provenance: target.provenance,
            conflict: target.conflict, purchaseGroupId: target.purchaseGroupId,
            volumeL: target.volumeL, unitPrice: target.unitPrice,
            fuelKind: target.fuelKind, fuelGrade: target.fuelGrade,
            isFull: target.isFull, tankLevelAfterPct: target.tankLevelAfterPct,
            stationId: target.stationId, crossCheck: target.crossCheck,
            extraction: target.extraction)
        guard let payload = try? PayloadCodec.encode(userVersion).payload else { return }
        let losingRecord = SyncRecord(
            id: target.id, entityType: FillUp.entityType,
            schemaVersion: PayloadCodec.currentSchemaVersion, payload: payload,
            clientUpdatedAt: target.updatedAt, deleted: false)
        try? repository.recordSyncOverwrite(
            recordId: target.id, losingRecord: losingRecord,
            deviceName: "iPad", at: now.addingTimeInterval(-2 * 86_400))
    }

    private static func tombstonedChargeIDs(in repository: TankbookRepository) -> [UUID] {
        (try? repository.deletedEntries())?
            .filter { $0.entry is ChargeSession }
            .map(\.id) ?? []
    }

    private static func makeStation(_ repository: TankbookRepository, name: String) -> Station {
        let now = Date()
        let station = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: nil)
        try? repository.upsertStation(station)
        return station
    }
}
#endif

/// Launch-argument fixtures for the screen's remaining sync-shaped surface.
/// The "Overwritten by sync" section is no longer here: it reads the real
/// `syncOverwrite` log through `RecentlyDeletedSyncOverwrites`.
struct RecentlyDeletedFixtures {
    var deletedOnDeviceByEntryID: [UUID: String]

    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> RecentlyDeletedFixtures {
        #if DEBUG
        var deletedOnDevice: [UUID: String] = [:]
        if arguments.contains("-forceRemovedElsewhere") {
            for id in RecentlyDeletedTestSeed.removedElsewhereIDs {
                // A device name is data, not copy: it arrives from the sync
                // payload and Apple does not translate its product names.
                deletedOnDevice[id] = "iPad"
            }
        }
        return RecentlyDeletedFixtures(deletedOnDeviceByEntryID: deletedOnDevice)
        #else
        return RecentlyDeletedFixtures(deletedOnDeviceByEntryID: [:])
        #endif
    }
}
