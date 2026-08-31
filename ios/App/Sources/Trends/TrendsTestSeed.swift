#if DEBUG
import Foundation
import TankbookCore

/// UI-test DB seeding for Trends (the same hook pattern as `HomeTestSeed`, and
/// the reason Trends' states are deterministic). Each `-seedHome*` argument
/// writes the smallest history that renders that state; combining with
/// `-homeResetDatabase` wipes the app database first so the states are isolated
/// from each other within a test run.
///
/// The arguments keep the `-seedHome` prefix so the two tabs share one seeding
/// vocabulary (and a single idempotence guard): a Trends seed and a Home seed
/// never double-plant a vehicle because whichever runs first seeds and the
/// other sees an occupied database and steps aside.
enum TrendsTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-seedHome") })
            || arguments.contains("-homeResetDatabase") else { return }

        // HomeTestSeed owns the reset and the Home-state seeds; delegate to it
        // so the reset happens exactly once and a Home seed (`-seedHomeFullHistory`,
        // `-seedHomeConflict`, ...) also works when the app lands on Trends.
        HomeTestSeed.seedIfRequested()

        let hasTrendsOnlyState = arguments.contains("-seedHomeFirstEstimate")
            || arguments.contains("-seedHomeExtendedWindow")
        guard hasTrendsOnlyState else { return }
        guard let repository = try? AppStore.repository() else { return }
        // Idempotent, exactly like HomeTestSeed: a seed that has already run
        // (or another state's seed) does not add a second vehicle.
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        if arguments.contains("-seedHomeFirstEstimate") {
            seedFirstEstimate(repository)
        } else if arguments.contains("-seedHomeExtendedWindow") {
            seedExtendedWindow(repository)
        }
    }

    /// Two full tanks close exactly one segment, so a headline exists but is
    /// below the floor - the honest label is "first estimate · 1 fill cycle"
    /// (docs/SCHEMA.md -> HEADLINE, D4-shaped).
    private static func seedFirstEstimate(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 16, odometer: 118_000, litres: 42.0,
                                  amount: "70.56", price: "1.676", stationID: nil)))
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 5, odometer: 118_800, litres: 41.4,
                                  amount: "69.14", price: "1.670", stationID: nil)))
    }

    /// Three segments but only two close inside 90 days, so the floor of 3
    /// pulls the window back to ~140 days and the label must say the REAL span
    /// - "last 5 months", never "last 3 months" (D3-shaped; the lie the rule
    /// exists to prevent).
    private static func seedExtendedWindow(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        for spec in [
            HomeTestSeed.FillSpec(daysAgo: 190, odometer: 118_000, litres: 47.0,
                                  amount: "78.77", price: "1.676", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 140, odometer: 118_690, litres: 48.5,
                                  amount: "81.29", price: "1.676", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 75, odometer: 119_340, litres: 45.0,
                                  amount: "75.42", price: "1.676", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 10, odometer: 119_980, litres: 44.5,
                                  amount: "74.57", price: "1.676", stationID: nil)
        ] {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: vehicle.id, spec))
        }
    }
}
#endif
