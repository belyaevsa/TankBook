#if DEBUG
import Foundation
import TankbookCore

/// UI-test / screenshot seeding for the RV.150 per-station settings surface
/// (the same hook pattern as `ManualFillUpTestSeed`). `-seedStationSettings`
/// writes the smallest garage that renders the captured-location state: one
/// vehicle, one prior fill naming a station whose location a fill-up save has
/// "captured" (plus its `lastUsedAt` and bought defaults), so the Stations list
/// has a row and the per-station settings pose has a location to show and to
/// clear. Idempotent: once a vehicle exists it does nothing.
///
/// `-seedUnlocatedStation` (a modifier on `-seedVehicleForUITests`) adds the
/// opposite fixture to the Confirm sheet's seed: a station with NO location and
/// NO lastUsedAt - the by-hand state RV.150 fixes - so the stamp-on-save is
/// exercisable end to end from the manual form.
enum StationSettingsTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedStationSettings") else { return }
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
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        // The station a save already stamped: location captured from the
        // forecourt fix, lastUsedAt and defaults written by the save.
        let station = Station(
            id: UUID.v7(), createdAt: now.addingTimeInterval(-20 * 86_400),
            updatedAt: now.addingTimeInterval(-2 * 86_400), deletedAt: nil,
            name: "Prima Auto", brand: nil,
            location: GeoCoordinate(latitude: 59.4378, longitude: 24.7536),
            favorite: false,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: now.addingTimeInterval(-2 * 86_400))
        try? repository.upsertStation(station)

        let priorDate = now.addingTimeInterval(-2 * 86_400)
        let prior = FillUp(
            id: UUID.v7(), createdAt: priorDate, updatedAt: priorDate, deletedAt: nil,
            vehicleId: vehicle.id, date: priorDate, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: station.id, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(prior)
    }
}
#endif
