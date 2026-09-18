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
            || arguments.contains("-seedHomeTwoWindows")
        guard hasTrendsOnlyState else { return }
        guard let repository = try? AppStore.repository() else { return }
        // Idempotent, exactly like HomeTestSeed: a seed that has already run
        // (or another state's seed) does not add a second vehicle.
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        if arguments.contains("-seedHomeFirstEstimate") {
            seedFirstEstimate(repository)
        } else if arguments.contains("-seedHomeExtendedWindow") {
            seedExtendedWindow(repository)
        } else if arguments.contains("-seedHomeTwoWindows") {
            seedTwoWindows(repository)
        }
    }

    /// Two full 90-day windows, three segments each (PJ.30): the older three
    /// at 7.5 L/100 km, the newer three at 6.0 - the hero tile's arrow reads
    /// "▼20%". The full-history seed has one segment in its previous window
    /// and so shows no arrow; this is the smallest history that shows one.
    private static func seedTwoWindows(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        // Eight full tanks 25 days apart, 600 km each: the fills at 150/125/100
        // days close the previous window's three segments (45 L each = 7.5),
        // the fills at 75/50/25/0 the current window's four (36 L each = 6.0).
        let litresByFill: [Double] = [42.0, 45.0, 45.0, 45.0, 36.0, 36.0, 36.0, 36.0]
        for (index, litres) in litresByFill.enumerated() {
            let daysAgo = 175 - index * 25
            let spec = HomeTestSeed.FillSpec(
                daysAgo: daysAgo, odometer: 118_000 + index * 600, litres: litres,
                amount: ManualFillUpFormat.decimal(Decimal(litres) * Decimal(string: "1.676")!, fractionDigits: 2),
                price: "1.676", stationID: nil)
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: vehicle.id, spec))
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
