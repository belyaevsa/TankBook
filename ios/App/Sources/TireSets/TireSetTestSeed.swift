#if DEBUG
import Foundation
import TankbookCore

/// UI-test + screenshot seeding for the Tire sets screen and the ServiceEntry
/// Tires mode (P3.3), the same idempotent hook pattern as `HomeTestSeed` /
/// `ReminderTestSeed`. `-seedTireSets` writes one vehicle with two seasonal
/// sets - "Winter Nokian" (mounted at 100 530 km, so its derived mileage is the
/// artboard's literal 18 400 km against the later 118 930 km fill) and "Summer
/// Michelin" (never mounted, so it renders "–") - and `-homeResetDatabase`
/// wipes the app database first so states are isolated within a run. The empty
/// state needs no seed: `-homeResetDatabase` alone leaves nothing to list.
enum TireSetTestSeed {
    /// The odometer the seeded mount record anchors on, and the odometer the
    /// later fill raises the car to. Their difference - 18 400 km - is the
    /// mileage the artboard spells for "Winter Nokian".
    static let mountOdometer = 100_530
    static let latestOdometer = 118_930

    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedTireSets")
            || arguments.contains("-seedTireSetsNoOdometer")
            || arguments.contains("-seedServiceEntryTires")
            || arguments.contains("-homeResetDatabase") else { return }

        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard arguments.contains("-seedTireSets")
            || arguments.contains("-seedTireSetsNoOdometer")
            || arguments.contains("-seedServiceEntryTires") else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        if arguments.contains("-seedTireSetsNoOdometer") {
            seedBare(repository)
        } else {
            seedFull(repository)
        }
    }

    // MARK: - Seeds

    /// The artboard state: two sets, the winter one mounted so its derived
    /// mileage is the literal 18 400 km, the summer one never mounted ("–").
    private static func seedFull(_ repository: TankbookRepository) {
        let now = Date()
        let vehicle = makeVehicle(initialOdometer: latestOdometer)
        try? repository.upsertVehicle(vehicle)

        let winter = TireSetDraft(name: "Winter Nokian").build(vehicleId: vehicle.id, now: now)
        let summer = TireSetDraft(name: "Summer Michelin")
            .build(vehicleId: vehicle.id, now: now.addingTimeInterval(1))
        try? repository.upsertTireSet(winter)
        try? repository.upsertTireSet(summer)

        // The swap that mounted the winter set, at a lower odometer than the
        // later fill - so its open span derives to the literal 18 400 km.
        let mountDate = now.addingTimeInterval(-60 * 86_400)
        let mount = ServiceRecord(
            id: UUID.v7(), createdAt: mountDate, updatedAt: mountDate, deletedAt: nil,
            vehicleId: vehicle.id, date: mountDate, odometer: mountOdometer,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: [],
            usedParts: [], tireSetId: winter.id, proposedReminderId: nil)
        try? repository.upsertServiceRecord(mount)

        let fillDate = now.addingTimeInterval(-10 * 86_400)
        let fill = FillUp(
            id: UUID.v7(), createdAt: fillDate, updatedAt: fillDate, deletedAt: nil,
            vehicleId: vehicle.id, date: fillDate, odometer: latestOdometer,
            money: Money(amount: Decimal(string: "61.20")!,
                         currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: 42.5, unitPrice: Decimal(string: "1.44")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(fill)
    }

    /// A vehicle with sets but NO odometer anywhere (no fill, no mount, nil
    /// initial): the Tires-mode mount's odometer is genuinely blank, so the
    /// L4 test can exercise "mounting makes the odometer required" without
    /// clearing a pre-filled field.
    private static func seedBare(_ repository: TankbookRepository) {
        let now = Date()
        let vehicle = makeVehicle(initialOdometer: nil)
        try? repository.upsertVehicle(vehicle)

        try? repository.upsertTireSet(
            TireSetDraft(name: "Winter Nokian").build(vehicleId: vehicle.id, now: now))
        try? repository.upsertTireSet(
            TireSetDraft(name: "Summer Michelin").build(vehicleId: vehicle.id,
                                                        now: now.addingTimeInterval(1)))
    }

    private static func makeVehicle(initialOdometer: Int?) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: initialOdometer)
    }

    /// The tire set the ServiceEntry Tires-mode screenshot pre-selects (the
    /// winter set, so the mount screenshot shows the derived 18 400 km lineage).
    @MainActor
    static func firstTireSetID() -> UUID? {
        guard let repository = try? AppStore.repository(),
              let vehicle = (try? repository.liveVehicles())?.first else { return nil }
        return (try? repository.liveTireSets(forVehicle: vehicle.id))?.first?.id
    }
}
#endif
