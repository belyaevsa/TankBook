import Foundation
import TankbookCore

/// UI-test seeding + sync-shaped presentation fixtures for the Recently
/// deleted screen (P1.7), the same pattern as `HomeTestSeed` and
/// `HomePresentables`.
///
/// The screen's real data is tombstones - `-seedRecentlyDeleted` writes a
/// vehicle and three entries (a fill, a charge, an expense) tombstoned at
/// ages that reproduce the artboard's countdowns (27/19/4 days left on the
/// run date), so the UI tests and screenshots match design/screens/
/// RecentlyDeleted.dc.html.
///
/// Everything sync-dependent is a FIXTURE, no real data exists until P4:
/// - `-forceSyncOverwritten` renders the "Overwritten by sync" section
///   (docs/SYNC.md S1/S4: the losing version is kept as the undo log).
/// - `-forceRemovedElsewhere` annotates the seeded charge as "removed on
///   iPad" (docs/SCHEMA.md: device attribution arrives via sync's
///   `origin_device`, not domain fields).
enum RecentlyDeletedTestSeed {
    /// Entry ids that sync says were deleted on another device. Populated by
    /// the seed under `-forceRemovedElsewhere`; empty in production until P4.
    /// `nonisolated(unsafe)` because it is fixture bookkeeping written and read
    /// on the main actor only (the view reads it while the seed is MainActor).
    nonisolated(unsafe) static var removedElsewhereIDs: Set<UUID> = []

    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let shouldSeed = arguments.contains("-seedRecentlyDeleted")
        let shouldReset = arguments.contains("-homeResetDatabase")
        guard shouldSeed || shouldReset else { return }

        if shouldReset {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        // Idempotent (same contract as HomeTestSeed): a run that already
        // seeded - or another suite's seed - is left alone.
        guard shouldSeed,
              (try? repository.liveVehicles())?.isEmpty != false else { return }

        seed(repository)

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
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
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
            recurrence: nil, installedInServiceId: nil)
        try? repository.upsertExpense(expense)
        try? repository.softDeleteExpense(id: expense.id, at: now.addingTimeInterval(-26 * 86_400))
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

/// A fixture row of the "Overwritten by sync" section (docs/SYNC.md S1/S4).
/// Presentational until the real merge log lands (P4) - the Compare affordance
/// is the only interaction, and the diff screen beyond it is out of scope for
/// P1.7.
struct SyncOverwrittenRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

/// Launch-argument fixtures for the sync-shaped surfaces of the screen.
struct RecentlyDeletedFixtures {
    var syncOverwritten: [SyncOverwrittenRow]
    var deletedOnDeviceByEntryID: [UUID: String]

    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> RecentlyDeletedFixtures {
        let now = Date()
        var syncRows: [SyncOverwrittenRow] = []
        if arguments.contains("-forceSyncOverwritten") {
            // The artboard's Shell row: replaced 2 days ago, 28 days left on
            // any run date.
            let replacedAt = now.addingTimeInterval(-2 * 86_400)
            let replacedDay = replacedAt.formatted(.dateTime.month(.abbreviated).day())
            let remaining = TombstoneCountdown.daysRemaining(deletedAt: replacedAt, now: now)
            let daysLeft = String(localized: "\(remaining) days left")
            syncRows = [SyncOverwrittenRow(
                title: "\(L10n.localize("Shell")) · \(L10n.localize("your version from iPhone"))",
                subtitle: [String(format: L10n.localize("Replaced %@"), replacedDay),
                           L10n.localize("odometer differed"),
                           daysLeft].joined(separator: " · "))]
        }

        var deletedOnDevice: [UUID: String] = [:]
        if arguments.contains("-forceRemovedElsewhere") {
            for id in RecentlyDeletedTestSeed.removedElsewhereIDs {
                // A device name is data, not copy: it arrives from the sync
                // payload and Apple does not translate its product names.
                deletedOnDevice[id] = "iPad"
            }
        }
        return RecentlyDeletedFixtures(syncOverwritten: syncRows,
                                       deletedOnDeviceByEntryID: deletedOnDevice)
    }
}
