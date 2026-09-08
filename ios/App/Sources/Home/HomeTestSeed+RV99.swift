#if DEBUG
import Foundation
import TankbookCore

extension HomeTestSeed {
    /// RV.99 RU-overflow screenshot state: a single car whose name is exactly
    /// 30 characters ("Škoda Октавия Универсал Бизнес" is 30). The delete
    /// confirmation composes the full name into the alert title, and a long RU
    /// name must not push the alert's buttons off screen - the phrase wraps,
    /// never the layout. Kept in its own file with RV.100 so `HomeTestSeed`
    /// stays under the type-body lint ceiling (the enum is at the limit).
    static func seedRV99LongName(_ repository: TankbookRepository) {
        var vehicle = makeVehicle()
        vehicle.name = "Škoda Октавия Универсал Бизнес"
        try? repository.upsertVehicle(vehicle)
    }

    /// RV.100 screenshot state: the ONLY car was JUST deleted. Seeds the single
    /// Volvo, then tombstones it through the same repository call the Vehicle
    /// detail delete confirmation runs (`softDeleteVehicle`) - so Home's load
    /// resolves an empty garage exactly as it does when the user deletes their
    /// last car, and the DB genuinely holds the tombstone (Recently deleted
    /// lists the car): never a fresh install. `simctl` cannot tap the
    /// confirmation, hence the hook, the same reason every other capture hook
    /// exists.
    static func seedDeleteLastCar(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        try? repository.softDeleteVehicle(id: vehicle.id)
    }
}
#endif
