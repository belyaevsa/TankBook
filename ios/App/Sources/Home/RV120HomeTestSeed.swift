#if DEBUG
import Foundation
import TankbookCore

/// RV.120's deterministic pattern: a 50 L tank corroborated by four 40 L full
/// fills every 10 days and 500 km apart (100 000 -> 101 500 km, 50 € each), so
/// the card reads 500 km between fills every 10 days, 625 km of range on the
/// last full tank (8.0 L/100km x 50 L, nothing driven since), and - when the
/// launch date is past day 7 with two of the fills in the month - the month's
/// pace. The seed writes fills, never figures.
enum RV120HomeTestSeed {
    static func seed(_ repository: TankbookRepository) {
        var vehicle = HomeTestSeed.makeVehicle()
        vehicle.tankCapacityL = 50
        try? repository.upsertVehicle(vehicle)
        for (index, daysAgo) in [40, 30, 20, 10].enumerated() {
            let fill = HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: daysAgo, odometer: 100_000 + index * 500, litres: 40.0,
                                      amount: "50.00", price: "1.250", stationID: nil))
            try? repository.upsertFillUp(fill)
        }
    }
}
#endif
