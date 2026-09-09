#if DEBUG
import Foundation
import TankbookCore

/// UI-test seeding for the ConfirmManual sheet. The `-seedVehicleForUITests`
/// launch argument creates one vehicle plus one prior fill-up (so the F9a
/// odometer-conflict quote can be exercised deterministically) without driving
/// the Add-car screen in every test - the same test-hook pattern as
/// `-forceCatalogUnavailable` on Add car. Idempotent: once a vehicle exists it
/// does nothing, so the app data survives across launches within a run.
///
/// The default seed car is metric (km). `-seedVehicleMiles` switches the same
/// seed to a miles-configured car (distance .mi, gallons, MPG) so the F9a quote
/// can be exercised on the units RV.126 found it lying about; the launch
/// argument stays a modifier on `-seedVehicleForUITests`, never a separate
/// harness flag, because WelcomeGate's tabbed-app decision keys on the parent
/// flag.
///
/// PJ.19 station suggestion fixture: `-seedStationSuggestion` (a modifier on
/// the same parent flag) adds two stations - a favourite ("Prima Auto") at a
/// fixed coordinate and a plain "Circle K Sadama" ~40 m east of it. The UI
/// tests inject the favourite's own coordinate with `-seedStationLocation`, so
/// rung 1 of the ranking (nearest favourite within 300 m) deterministically
/// proposes Prima Auto and the row is then provably changeable.
enum ManualFillUpTestSeed {
    /// The seeded car's fuel kinds, from a launch argument (P2.3b). The
    /// default is a single-kind petrol car - the only kind of car that exists
    /// in the singular - and the variant arguments seed the shapes the Fuel
    /// row must render differently: a diesel-only car, a two-grade petrol car,
    /// and a real bi-fuel petrol + LPG car. The variants are why the fuel-row
    /// tests can assert WHICH kinds a car is offered, never just how many.
    static func fuelKindsFromArguments(_ arguments: [String]) -> [FuelKind] {
        if arguments.contains("-seedVehicleDieselOnly") { return [.diesel] }
        if arguments.contains("-seedVehicleDieselLPG") { return [.diesel, .lpg] }
        if arguments.contains("-seedVehiclePetrolMulti") { return [.petrol92, .petrol95] }
        if arguments.contains("-seedVehiclePetrolLPG") { return [.petrol95, .lpg] }
        return [.petrol95]
    }

    /// The seed car's unit set. Metric by default; `-seedVehicleMiles` makes it
    /// an imperial car (miles, US gallons, MPG) so unit-labelled copy can be
    /// exercised on a miles vehicle - the RV.126 shape.
    static func unitsFromArguments(_ arguments: [String]) -> Vehicle.Units {
        if arguments.contains("-seedVehicleMiles") {
            return Vehicle.Units(distance: .mi, volume: .galUS,
                                 consumption: .mpgUS, energy: .miPerKWh)
        }
        return Vehicle.Units(distance: .km, volume: .l,
                             consumption: .lPer100, energy: .kWhPer100)
    }

    /// The prior fill's odometer and the car's initial reading. The metric seed
    /// keeps the documented 119 486 km (the F9a quote example everywhere in the
    /// docs); the miles seed uses a plausible 74 286 mi so the quote reads like
    /// a miles car, never a km figure wearing a mi label.
    static func initialOdometerFromArguments(_ arguments: [String]) -> Int {
        arguments.contains("-seedVehicleMiles") ? 74_286 : 119_486
    }

    @MainActor
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedVehicleForUITests") else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let arguments = ProcessInfo.processInfo.arguments
        let fuelKinds = fuelKindsFromArguments(arguments)
        let units = unitsFromArguments(arguments)
        let initialOdometer = initialOdometerFromArguments(arguments)
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: fuelKinds,
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: units,
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: initialOdometer)
        try? repository.upsertVehicle(vehicle)

        // A prior fill-up six days ago at the initial odometer - the F9a quote
        // example ("Aug 17 already recorded 119 486 km.") and the odometer
        // pre-fill. The fill uses the car's own usual kind, so a diesel-only
        // seed's prior fill is a diesel fill, not a mis-labelled petrol one.
        let priorDate = now.addingTimeInterval(-6 * 86_400)
        let prior = FillUp(
            id: UUID.v7(), createdAt: priorDate, updatedAt: priorDate, deletedAt: nil,
            vehicleId: vehicle.id, date: priorDate, odometer: initialOdometer,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: fuelKinds.first ?? .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(prior)

        // PJ.19: the two-station fixture (see the type doc). Coordinates are
        // fixed so a test-injected location can make a specific station the
        // ranking's winner deterministically.
        if arguments.contains("-seedStationSuggestion") {
            seedStationSuggestionStations(repository: repository, now: now)
        }

        // RV.150: the by-hand fixture. `-seedUnlocatedStation` adds ONE station
        // with NO location and NO lastUsedAt - the exact state that hid the
        // defect (a by-hand user's stations could never rank) - so a Confirm
        // save can be proven to stamp it end to end.
        if arguments.contains("-seedUnlocatedStation") {
            let unlocated = Station(
                id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
                name: "Prima Auto", brand: nil, location: nil, favorite: false,
                defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil),
                lastUsedAt: nil)
            try? repository.upsertStation(unlocated)
        }
    }

    /// The two stations of the PJ.19 fixture. Prima Auto is the favourite at
    /// the coordinate the tests inject; Circle K Sadama is ~40 m east, not a
    /// favourite and never used, so it can only win after the user's own menu
    /// pick - never from rung 1.
    private static func seedStationSuggestionStations(repository: TankbookRepository,
                                                      now: Date) {
        let prima = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Prima Auto", brand: nil,
            location: GeoCoordinate(latitude: 59.4378, longitude: 24.7536),
            favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: nil)
        let circleK = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Circle K Sadama", brand: nil,
            location: GeoCoordinate(latitude: 59.4378, longitude: 24.7543),
            favorite: false,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: nil)
        try? repository.upsertStation(prima)
        try? repository.upsertStation(circleK)
    }
}
#endif
