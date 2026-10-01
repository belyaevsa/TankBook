#if DEBUG
import Foundation
import TankbookCore

/// A deterministic AdBlue state: a diesel car with three full fills and one or
/// two AdBlue top-ups between them, so Home's car card carries the AdBlue line
/// (one top-up: the rate is a dash; two: 8 L over 2200 km = 3.6 L/1000 km) and
/// Trends its AdBlue card at the second top-up.
enum P114HomeTestSeed {
    static var actions: [(argument: String, seed: (TankbookRepository) -> Void)] { [
        ("-seedHomeAdBlueOne", seedOne),
        ("-seedHomeAdBlueTwo", seedTwo),
    ] }

    static func seedOne(_ repository: TankbookRepository) { seed(repository, topUps: 1) }
    static func seedTwo(_ repository: TankbookRepository) { seed(repository, topUps: 2) }

    private static func seed(_ repository: TankbookRepository, topUps: Int) {
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Passat", make: "Volkswagen", model: "Passat", year: 2019, plate: nil,
            powertrain: .ice, fuelKinds: [.diesel], tankCapacityL: 66,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 120_000)
        try? repository.upsertVehicle(vehicle)

        for (daysAgo, odometer) in [(40, 120_500), (25, 121_400), (6, 122_300)] {
            let day = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            try? repository.upsertFillUp(FillUp(
                id: UUID.v7(), createdAt: day, updatedAt: day, vehicleId: vehicle.id,
                date: day, odometer: odometer,
                money: Money(amount: Decimal(string: "82.40")!, currency: .eur, homeCurrency: .eur),
                provenance: .manual, volumeL: 51.5, unitPrice: Decimal(string: "1.6"),
                fuelKind: .diesel, isFull: true, tankLevelAfterPct: 100, crossCheck: .verified))
        }
        let topUpDays: [(daysAgo: Int, odometer: Int, litres: Double)] = [(30, 120_100, 10), (3, 122_300, 8)]
        for topUp in topUpDays.suffix(topUps) {
            let day = now.addingTimeInterval(-Double(topUp.daysAgo) * 86_400)
            try? repository.upsertAdBlueFill(AdBlueFill(
                id: UUID.v7(), createdAt: day, updatedAt: day, vehicleId: vehicle.id,
                date: day, odometer: topUp.odometer,
                money: Money(amount: Decimal(topUp.litres) * Decimal(string: "0.899")!,
                             currency: .eur, homeCurrency: .eur),
                provenance: .manual, volumeL: topUp.litres, unitPrice: Decimal(string: "0.899")))
        }
    }
}
#endif
