import Foundation
import TankbookCore

/// UI-test DB seeding for Home (the same hook pattern as `ManualFillUpTestSeed`,
/// and the reason Home's five states are deterministic). Each `-seedHome*`
/// argument writes the smallest history that renders that state; combining with
/// `-homeResetDatabase` wipes the app database first so the five states are
/// isolated from each other within a test run.
///
/// Real-data states (vehicle presence, entry presence, D4) are seeded here.
/// Everything sync-dependent (S2/S5/S7, reminder banner, guest chrome) is a
/// presentation fixture in `HomePresentables` - no real data exists until P4.
enum HomeTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-seedHome") })
            || arguments.contains("-homeResetDatabase") else { return }

        if arguments.contains("-homeResetDatabase") {
            try? AppStore.resetForTests()
        }
        guard let repository = try? AppStore.repository() else { return }
        // Idempotent: a seed that has already run (or another test's seed) does
        // not add a second vehicle, so app data survives across launches within
        // a run - matching ManualFillUpTestSeed's contract.
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        if arguments.contains("-seedHomeEmptyVehicle") {
            seedEmptyVehicle(repository)
        } else if arguments.contains("-seedHomeSingleFill") {
            seedSingleFill(repository)
        } else if arguments.contains("-seedHomeFullHistory") {
            seedFullHistory(repository)
        } else if arguments.contains("-seedHomeConflict") {
            seedConflict(repository)
        }
    }

    // MARK: - Seeds

    private static func seedEmptyVehicle(_ repository: TankbookRepository) {
        try? repository.upsertVehicle(makeVehicle())
    }

    /// The D4 state: a car, one full tank logged, no segment closed yet.
    private static func seedSingleFill(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let fill = makeFill(vehicleID: vehicle.id,
                            FillSpec(daysAgo: 6, odometer: 118_000, litres: 42.3,
                                     amount: "71.02", price: "1.679", stationID: nil))
        try? repository.upsertFillUp(fill)
    }

    /// A five-month fill history: closed segments, a headline, current-month
    /// spend, last price per litre and a recent-entries section - the "Full"
    /// state (design/screens/HomeA.dc.html).
    private static func seedFullHistory(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository, name: "Shell")
        let neste = makeStation(repository, name: "Neste")

        let fills: [FillUp] = [
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 150, odometer: 118_000, litres: 42.1,
                              amount: "70.56", price: "1.676", stationID: shell.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 120, odometer: 118_800, litres: 41.4,
                              amount: "69.14", price: "1.670", stationID: neste.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 90, odometer: 119_600, litres: 43.0,
                              amount: "71.17", price: "1.655", stationID: shell.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 60, odometer: 120_400, litres: 40.6,
                              amount: "66.18", price: "1.630", stationID: neste.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 30, odometer: 121_200, litres: 42.8,
                              amount: "69.90", price: "1.633", stationID: shell.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 7, odometer: 122_000, litres: 41.2,
                              amount: "66.90", price: "1.624", stationID: neste.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 2, odometer: 122_800, litres: 43.5,
                              amount: "71.02", price: "1.633", stationID: shell.id)),
            // A fill today guarantees current-month spend exists on any run
            // date, so the "Full" state always renders the month-spend vital.
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 0, odometer: 123_600, litres: 42.0,
                              amount: "68.46", price: "1.630", stationID: neste.id))
        ]
        for fill in fills {
            try? repository.upsertFillUp(fill)
        }
    }

    /// The F9a/S3 conflict state: a fill whose odometer breaks the timeline, so
    /// Home shows the amber badge and the "1 entry excluded" footnote.
    private static func seedConflict(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let flagged = makeFill(
            vehicleID: vehicle.id,
            FillSpec(daysAgo: 2, odometer: 117_900, litres: 43.5,
                     amount: "71.02", price: "1.633", stationID: nil),
            conflict: .flagged(kind: .order, detectedAt: Date()))
        try? repository.upsertFillUp(flagged)
        try? repository.upsertFillUp(
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 15, odometer: 118_500, litres: 41.2,
                              amount: "66.90", price: "1.624", stationID: nil)))
        try? repository.upsertFillUp(
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 30, odometer: 118_000, litres: 42.8,
                              amount: "69.90", price: "1.633", stationID: nil)))
    }

    // MARK: - Fixture builders

    private static func makeVehicle() -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
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

    /// A fixture fill's data, kept apart from the construction call so the
    /// builder stays small (swiftlint function_parameter_count).
    private struct FillSpec {
        let daysAgo: Int
        let odometer: Int
        let litres: Double
        let amount: String
        let price: String
        let stationID: UUID?
    }

    private static func makeFill(vehicleID: UUID, _ spec: FillSpec,
                                 conflict: ConflictState = .none) -> FillUp {
        let date = Date().addingTimeInterval(-Double(spec.daysAgo) * 86_400)
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: spec.odometer,
            money: Money(amount: Decimal(string: spec.amount)!,
                         currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: conflict,
            purchaseGroupId: nil, volumeL: spec.litres, unitPrice: Decimal(string: spec.price)!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: spec.stationID, crossCheck: .verified, extraction: nil)
    }
}
