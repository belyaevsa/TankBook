#if DEBUG
import Foundation
import TankbookCore

/// RV.141 seed: a history with BOTH exclusion causes present at once - an
/// unresolved duplicate pair AND a timeline-conflicted entry - so a footnote
/// that counts N > 1 opens the excluded-entries list with rows of both reasons.
/// Kept in its own type so `HomeTestSeed` stays under its lint body budget.
enum ExcludedEntriesTestSeed {
    /// One car with:
    /// - an unresolved S2 pair (two Shell fills 15 minutes apart, volumes within
    ///   5%, same odometer - the excluded member is out of every figure), and
    /// - a conflicted fill (5 days ago at 117 900, below its 118 500
    ///   predecessor) - the F9a/S3 shape `seedOrderConflict` uses, flagged
    ///   explicitly so it re-derives the same way on any later validation.
    /// The count is therefore 2, and the reasons differ across the two rows.
    static func seed(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository, name: "Shell")

        // Timeline base: two older fills the conflicted one can break against.
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 30, odometer: 118_000, litres: 42.8,
                                                        amount: "69.90", price: "1.633", stationID: shell.id)))
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 15, odometer: 118_500, litres: 41.2,
                                                        amount: "66.90", price: "1.624", stationID: shell.id)))
        // The conflicted entry: newest at the time, reading below its previous.
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 5, odometer: 117_900, litres: 43.5,
                                                        amount: "71.02", price: "1.633", stationID: shell.id),
                                  conflict: .flagged(kind: .order, detectedAt: Date())))

        // The duplicate pair: one physical fill logged twice, 1 day ago.
        let pairDate = Date().addingTimeInterval(-1 * 86_400)
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 1, odometer: 122_800, litres: 42.3,
                                                        amount: "71.02", price: "1.679", stationID: shell.id),
                                  date: pairDate))
        try? repository.upsertFillUp(
            HomeTestSeed.makeFill(vehicleID: vehicle.id,
                                  HomeTestSeed.FillSpec(daysAgo: 1, odometer: 122_800, litres: 42.9,
                                                        amount: "72.05", price: "1.679", stationID: shell.id),
                                  date: pairDate.addingTimeInterval(15 * 60)))
    }

    /// RV.133-style pose: when `-presentScreen excludedEntries` shows this list
    /// directly, the underlying Home root may not have seeded yet (simctl cannot
    /// tap through the footnote), so the screen seeds its own data. Idempotent -
    /// a Home that already seeded leaves the repository occupied and this steps
    /// aside - and inert in every footnote-reached flow.
    @MainActor
    static func seedForDirectPresentIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-presentScreen"),
              ProcessInfo.processInfo.arguments.contains("excludedEntries") else { return }
        guard let repository = try? AppStore.repository(),
              (try? repository.liveVehicles())?.isEmpty != false else { return }
        seed(repository)
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
}
#endif
