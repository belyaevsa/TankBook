#if DEBUG
import Foundation
import TankbookCore

/// The pump-mark pose: two fills, the newer one read from a pump display
/// (`Provenance.pumpPhoto`), so the Log shows the pump mark on one row and not
/// on the typed one. The seed writes entries, never the mark.
enum PumpReadHomeTestSeed {
    static func seed(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let typed = HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 12, odometer: 118_000, litres: 41.2,
                                  amount: "69.18", price: "1.679", stationID: nil))
        var read = HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 2, odometer: 118_640, litres: 38.32,
                                  amount: "64.34", price: "1.679", stationID: nil))
        read.provenance = .pumpPhoto
        try? repository.upsertFillUp(typed)
        try? repository.upsertFillUp(read)
    }
}
#endif
