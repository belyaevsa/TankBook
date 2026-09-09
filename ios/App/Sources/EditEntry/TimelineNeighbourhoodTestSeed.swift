#if DEBUG
import Foundation
import TankbookCore

/// RV.117b test seeds shared by the two doors that render the neighbourhood
/// panel - Edit entry (`-seedEditEntryConflict*`) and the Settings flagged list
/// (`-seedSettingsFlaggedNeighbourhood`). Kept in their own type so neither
/// `HomeTestSeed` nor `EditEntryTestSeed` grows past its lint body budget, and
/// so the two doors provably start from identical data.
enum TimelineNeighbourhoodTestSeed {
    /// The F9a/S3 conflict state: a fill whose odometer breaks the timeline, so
    /// Home shows the amber badge and the "1 entry excluded" footnote. The
    /// flagged fill is the NEWEST entry (2 days ago) and genuinely re-flags on
    /// validation - its reading 117 900 sits below its previous 118 500 - so
    /// opening it re-derives the flag and the panel has a real range to draw.
    static func seedOrderConflict(_ repository: TankbookRepository,
                                  vehicle: Vehicle? = nil) {
        let vehicle = vehicle ?? HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let flagged = HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 2, odometer: 117_900, litres: 43.5,
                                  amount: "71.02", price: "1.633", stationID: nil),
            conflict: .flagged(kind: .order, detectedAt: Date()))
        try? repository.upsertFillUp(flagged)
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 15, odometer: 118_500, litres: 41.2,
                                                        amount: "66.90", price: "1.624", stationID: nil)))
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 30, odometer: 118_000, litres: 42.8,
                                                        amount: "69.90", price: "1.633", stationID: nil)))
    }

    /// A PACE conflict, for the open-ended date sentence ("no earlier than
    /// ..."). On a car whose pace limit is 20 km/day, the newest fill's 100 900
    /// reading implies 900 km over the 40 days since the previous fill -
    /// 22.5 km/day, over the limit. Its odometer interval is bounded
    /// (100 001 ... 100 800) while its date interval has an OPEN upper end
    /// (no next entry), so the date sentence renders "no earlier than ..." - the
    /// case a middle-entry test never produces.
    static func seedPaceConflict(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle(paceLimitKmPerDay: 20)
        try? repository.upsertVehicle(vehicle)
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 40, odometer: 100_000, litres: 41.2,
                                                        amount: "66.90", price: "1.624", stationID: nil)))
        let flagged = HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 0, odometer: 100_900, litres: 42.3,
                                  amount: "71.02", price: "1.679", stationID: nil),
            conflict: .flagged(kind: .pace, detectedAt: Date()))
        try? repository.upsertFillUp(flagged)
    }
}
#endif
