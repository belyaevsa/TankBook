import Foundation
import TankbookCore

/// UI-test DB seeding for the Car switcher (the same hook pattern as
/// `TrendsTestSeed`). `HomeTestSeed` owns the reset (`-homeResetDatabase`) and
/// the shared idempotence guard; the two `-seedHomeCarSwitcher*` states below
/// build the switcher's data:
///
/// - `-seedHomeCarSwitcher` - the artboard's garage: a petrol car (reports
///   L/100), an EV (reports kWh/100 - the per-vehicle unit contrast the sheet
///   exists to show) and an archived car, dimmed and out of active stats but
///   with its history kept.
/// - `-seedHomeCarSwitcherLimit` - three live cars AT the free-tier cap plus an
///   archived car, so "Add car" must show the limit sheet
///   (docs/ERRORS.md -> Car switcher / Garage).
enum CarSwitcherTestSeed {
    @MainActor
    static func seedIfRequested() {
        // The `-seedHomeCarSwitcher*` actions live in HomeTestSeed's action
        // table (so Home also seeds them at launch); delegate so the reset and
        // the idempotence guard happen exactly once, like TrendsTestSeed.
        HomeTestSeed.seedIfRequested()
    }

    // MARK: - The artboard's garage

    /// A petrol car with a closed history (reports L/100), an EV with charge
    /// sessions (reports kWh/100) and an archived car. The Volvo reuses the D1
    /// golden series so its odometer lands on the artboard's 119 486 km; the
    /// ID.4's two charges close one segment at 17.8 kWh/100.
    static func seedGarage(_ repository: TankbookRepository) {
        seedPetrolCar(repository)
        seedEV(repository)
        seedArchivedCar(repository)
    }

    /// The Volvo V60: the D1 golden series so its odometer lands on the
    /// artboard's 119 486 km (reports L/100).
    private static func seedPetrolCar(_ repository: TankbookRepository) {
        let now = Date()
        let volvo = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
        try? repository.upsertVehicle(volvo)
        for spec in [
            HomeTestSeed.FillSpec(daysAgo: 98, odometer: 114_980, litres: 45.9,
                                  amount: "77.02", price: "1.678", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 84, odometer: 115_622, litres: 44.6,
                                  amount: "74.51", price: "1.671", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 70, odometer: 116_281, litres: 46.8,
                                  amount: "77.99", price: "1.667", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 56, odometer: 116_904, litres: 43.1,
                                  amount: "71.62", price: "1.662", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 42, odometer: 117_561, litres: 45.5,
                                  amount: "75.30", price: "1.655", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 28, odometer: 118_207, litres: 44.2,
                                  amount: "72.96", price: "1.651", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 14, odometer: 118_843, litres: 43.9,
                                  amount: "72.42", price: "1.650", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 1, odometer: 119_486, litres: 42.3,
                                  amount: "71.02", price: "1.679", stationID: nil)
        ] {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: volvo.id, spec))
        }
    }

    /// The ID.4 (reports kWh/100): the engine's EV segment carries the CLOSING
    /// charge's energy (ConsumptionEngine.evSegments) - 54 kWh over 303 km ->
    /// 17.8 kWh/100, and the closing odometer is the artboard's 31 240 km.
    private static func seedEV(_ repository: TankbookRepository) {
        let now = Date()
        let id4 = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "ID.4", make: "Volkswagen", model: "ID.4", year: 2022,
            plate: nil, powertrain: .ev, fuelKinds: [.electricity],
            tankCapacityL: nil, batteryCapacityKWh: 77, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 30_000)
        try? repository.upsertVehicle(id4)
        try? repository.upsertChargeSession(HomeTestSeed.makeCharge(
            vehicleID: id4.id,
            HomeTestSeed.ChargeSpec(daysAgo: 12, odometer: 30_937, energyKWh: 60,
                                    amount: "21.50", provider: "Ionity")))
        try? repository.upsertChargeSession(HomeTestSeed.makeCharge(
            vehicleID: id4.id,
            HomeTestSeed.ChargeSpec(daysAgo: 3, odometer: 31_240, energyKWh: 54,
                                    amount: "19.50", provider: "Ionity")))
    }

    /// The BMW 320d, archived (J13): history kept in the repository, out of the
    /// active stats, dimmed in the switcher.
    private static func seedArchivedCar(_ repository: TankbookRepository) {
        let now = Date()
        let bmw = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "BMW 320d", make: "BMW", model: "320d", year: 2019,
            plate: nil, powertrain: .ice, fuelKinds: [.diesel],
            tankCapacityL: 56, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: true, paceLimitKmPerDay: 1500,
            initialOdometer: 96_000)
        try? repository.upsertVehicle(bmw)
        try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: bmw.id,
            HomeTestSeed.FillSpec(daysAgo: 200, odometer: 95_000, litres: 47.0,
                                  amount: "72.85", price: "1.550", stationID: nil)))
        try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: bmw.id,
            HomeTestSeed.FillSpec(daysAgo: 90, odometer: 96_000, litres: 46.2,
                                  amount: "71.61", price: "1.550", stationID: nil)))
    }

    // MARK: - The car-limit state

    /// Three live cars sit AT the free-tier cap and one archived car has freed
    /// nothing - so "Add car" must refuse and show the limit sheet. Existing
    /// cars stay fully usable (the anti-CarScope rule).
    static func seedLimit(_ repository: TankbookRepository) {
        let now = Date()
        let live = [
            ("Volvo V60", Powertrain.ice),
            ("ID.4", Powertrain.ev),
            ("Kia Niro", Powertrain.hybrid)
        ]
        for (name, powertrain) in live {
            let fuelKinds: [FuelKind] = powertrain == .ev ? [.electricity] : [.petrol95, .diesel]
            try? repository.upsertVehicle(Vehicle(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                name: name, make: nil, model: nil, year: 2021, plate: nil,
                powertrain: powertrain, fuelKinds: fuelKinds,
                tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l,
                                      consumption: .lPer100, energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500,
                initialOdometer: 60_000))
        }
        try? repository.upsertVehicle(Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "BMW 320d", make: "BMW", model: "320d", year: 2019, plate: nil,
            powertrain: .ice, fuelKinds: [.diesel], tankCapacityL: 56,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l,
                                  consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: true, paceLimitKmPerDay: 1500,
            initialOdometer: 96_000))
    }
}
