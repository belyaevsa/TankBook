#if DEBUG
import Foundation
import TankbookCore

/// UI-test and screenshot seeding for the inbox (RV.38, RV.45).
///
/// Three seeds, each idempotent (once a vehicle exists it no-ops) under the same
/// `-homeResetDatabase` gate:
///
/// - `-seedInboxItem` (RV.38): one fill-up with a BLANK price plus a pending item
///   whose reading fills that price and disagrees with the typed total - the
///   shape that lets the decline/accept suites assert hard rule 13. The RICH
///   case (five differing fields) is the RV.38 bell screenshot.
/// - `-seedInboxComparison` (RV.45): exactly ONE differing field (volume) and
///   ONE blank field (unit price), everything else agreeing. That is the
///   "interesting case" the comparison card must render, and the shape that
///   lets the L4 suite assert exactly two ticks and the per-field merge.
/// - `-seedInboxNothingToChange` (RV.45 honesty rule 2): an item whose reading
///   AGREES with the saved entry - the no-op card must say so and offer no
///   update action.
enum InboxTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedInboxItem") {
            seedRichItem()
        }
        if arguments.contains("-seedInboxComparison") {
            seedComparisonItem()
        }
        if arguments.contains("-seedInboxNothingToChange") {
            seedNothingToChangeItem()
        }
    }

    // MARK: - RV.38 the rich item (blank price + five differing fields)

    @MainActor
    private static func seedRichItem() {
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

    // MARK: - RV.45 the comparison case (one differing + one blank field)

    @MainActor
    private static func seedComparisonItem() {
        let arguments = ProcessInfo.processInfo.arguments
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

        // The saved entry: total + litres typed, the price left BLANK - exactly
        // one blank (unit price) and one value the receipt reads differently
        // (volume 40.00 vs 30.00). Everything else the receipt reads agrees, so
        // the card offers exactly two ticks.
        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "100.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 40.00, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
        try? repository.upsertFillUp(fill)

        // volume 30.00 DIFFERS (replaces 40.00); unitPrice 1.800 FILLS the blank.
        // total / fuel kind / currency agree; date is unread (nil), so it is not
        // listed - the card must not treat an unread field as a decision.
        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "100.00")!, confidence: 0.92),
            volume: .init(value: 30.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.800")!, confidence: 0.88),
            fuelKind: .init(value: .petrol95, confidence: 0.70),
            currency: .init(value: .eur, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }

    // MARK: - RV.45 the nothing-to-change case (the reading agrees)

    @MainActor
    private static func seedNothingToChangeItem() {
        let arguments = ProcessInfo.processInfo.arguments
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

        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(fill)

        // The reading AGREES with every field the entry holds; the date is
        // unread. An agreeing answer would never be offered an item in the real
        // path, but the entry may have changed after the item was created - the
        // card must then say "nothing to change" and offer no update.
        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "71.02")!, confidence: 0.92),
            volume: .init(value: 42.30, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.88),
            fuelKind: .init(value: .petrol95, confidence: 0.70),
            currency: .init(value: .eur, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }
}
#endif
