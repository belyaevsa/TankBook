#if DEBUG
import Foundation
import TankbookCore

/// RV.66: TWO live cars, the conflict on the NON-selected one. Car A is
/// inserted FIRST so it is the default selection (`VehicleSelection` falls back
/// to the first live car) and its log is clean; car B carries one out-of-order
/// flagged fill at a station only it uses. The account-wide
/// `flaggedEntryCount` is 1 while the selected car's Home shows no badge at all
/// - the exact asymmetry RV.66 exists because of. Everything is written
/// `.synced` (no dirty queue), so the chip derives `.synced` + the warn dot
/// rather than the "waiting" state a dirty seed would show. Sync-state scn
/// values are sequential per record exactly as `SettingsTestSeed` writes them.
///
/// A separate seed type (not another `HomeTestSeed` action) because the seed
/// pushed that enum's body over the linter's type-body limit - the same
/// split-for-lint reason `EditEntryView+Discard.swift` exists.
enum RV66TwoCarTestSeed {
    static func seed(_ repository: TankbookRepository) {
        let now = Date()
        let carA = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .lpg],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
        try? repository.upsertVehicle(carA, syncState: .synced(scn: 1))
        let shell = makeStation(repository, name: "Shell")
        try? repository.upsertStation(shell, syncState: .synced(scn: 2))
        var scn: Int64 = 3
        for spec in [
            HomeTestSeed.FillSpec(daysAgo: 30, odometer: 119_600, litres: 43.0,
                                  amount: "71.17", price: "1.655", stationID: shell.id),
            HomeTestSeed.FillSpec(daysAgo: 5, odometer: 120_400, litres: 40.6,
                                  amount: "66.18", price: "1.630", stationID: shell.id)
        ] {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: carA.id, spec),
                                         syncState: .synced(scn: scn))
            scn += 1
        }

        let carB = Vehicle(
            id: UUID.v7(), createdAt: now.addingTimeInterval(1), updatedAt: now,
            deletedAt: nil, name: "Golf GTI", make: "Volkswagen", model: "Golf GTI",
            year: 2019, plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 50, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 86_000)
        try? repository.upsertVehicle(carB, syncState: .synced(scn: scn))
        scn += 1
        // The older fill at 88 000 km makes the newer 87 500 km fill out of
        // order - the flagged entry's odometer genuinely breaks the timeline.
        let rocket = makeStation(repository, name: "Rocket Fuel")
        try? repository.upsertStation(rocket, syncState: .synced(scn: scn))
        scn += 1
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: carB.id,
                                  HomeTestSeed.FillSpec(daysAgo: 60, odometer: 88_000,
                                                        litres: 41.0, amount: "68.50",
                                                        price: "1.671", stationID: nil)),
            syncState: .synced(scn: scn))
        scn += 1
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: carB.id,
                                  HomeTestSeed.FillSpec(daysAgo: 2, odometer: 87_500,
                                                        litres: 42.3, amount: "71.02",
                                                        price: "1.679", stationID: rocket.id),
                                  conflict: .flagged(kind: .order, detectedAt: Date())),
            syncState: .synced(scn: scn))
    }

    /// The station builder `HomeTestSeed.makeStation` (private there) needs,
    /// written synced so the seed leaves no dirty queue behind.
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
