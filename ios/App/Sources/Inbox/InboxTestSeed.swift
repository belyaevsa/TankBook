#if DEBUG
import Foundation
import TankbookCore

/// UI-test and screenshot seeding for the inbox (RV.38). `-seedInboxItem` seeds
/// one vehicle plus one fill-up with a BLANK price - the one gateway field a
/// saved fill-up can genuinely leave blank (an imported or partially-written
/// row) - and one pending inbox item whose reading fills that price (1.679) and
/// disagrees with the typed total (99.99 vs 71.02). That shape is what lets the
/// L4 suite assert the two halves of hard rule 13: accepting fills the blank
/// price, and leaves the typed total and litres byte-identical.
///
/// Idempotent (once a vehicle exists it no-ops), the same `-homeResetDatabase`
/// reset gate as the other seeds (AppStore.resetForTestsOncePerLaunch makes the
/// wipe run at most once per launch).
enum InboxTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedInboxItem") else { return }
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l,
                                 consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        // The saved entry: typed total + litres, the price left blank - exactly
        // the shape an accepted update must fill, never a value it must
        // overwrite.
        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
        try? repository.upsertFillUp(fill)

        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.92),
            volume: .init(value: 55.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.500")!, confidence: 0.88),
            date: .init(value: "17.08.2026", confidence: 0.80),
            fuelKind: .init(value: .diesel, confidence: 0.70),
            currency: .init(value: .rub, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }
}
#endif
