#if DEBUG
import Foundation
import TankbookCore

/// UI-test seeding for the ConfirmManual sheet. The `-seedVehicleForUITests`
/// launch argument creates one vehicle plus one prior fill-up (so the F9a
/// odometer-conflict quote can be exercised deterministically) without driving
/// the Add-car screen in every test - the same test-hook pattern as
/// `-forceCatalogUnavailable` on Add car. Idempotent: once a vehicle exists it
/// does nothing, so the app data survives across launches within a run.
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

    @MainActor
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedVehicleForUITests") else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let fuelKinds = fuelKindsFromArguments(ProcessInfo.processInfo.arguments)
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: fuelKinds,
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        // A prior fill-up six days ago at 119 486 km - the F9a quote example
        // ("Aug 17 already recorded 119 486 km.") and the odometer pre-fill.
        // The fill uses the car's own usual kind, so a diesel-only seed's
        // prior fill is a diesel fill, not a mis-labelled petrol one.
        let priorDate = now.addingTimeInterval(-6 * 86_400)
        let prior = FillUp(
            id: UUID.v7(), createdAt: priorDate, updatedAt: priorDate, deletedAt: nil,
            vehicleId: vehicle.id, date: priorDate, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: fuelKinds.first ?? .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(prior)
    }
}
#endif
