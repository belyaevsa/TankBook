#if DEBUG
import Foundation
import TankbookCore

/// `-seedHomeArchivedReturned`: the S5 state through the REAL path - a second
/// car this device deleted, brought back by an entry that arrived for it via
/// `resurrectArchivedIfTombstoned`, so the notice the card renders is the
/// resurrection's own row and never a painted fixture. The live car keeps Home
/// on its dashboard; the returned one sits archived in the Garage.
enum VehicleReturnTestSeed {
    static func seed(_ repository: TankbookRepository) {
        try? repository.upsertVehicle(HomeTestSeed.makeVehicle())

        var sold = HomeTestSeed.makeVehicle()
        sold.name = "Saab 9-3"
        sold.make = "Saab"
        sold.model = "9-3"
        try? repository.upsertVehicle(sold, syncState: .synced(scn: 1))
        try? repository.softDeleteVehicle(id: sold.id)
        let lastFill = HomeTestSeed.makeFill(
            vehicleID: sold.id,
            HomeTestSeed.FillSpec(daysAgo: 1, odometer: 118_400, litres: 40.1,
                                  amount: "66.50", price: "1.659", stationID: nil))
        try? repository.upsertFillUp(lastFill, syncState: .synced(scn: 2))
        try? repository.resurrectArchivedIfTombstoned(vehicleId: sold.id)
    }
}
#endif
