#if DEBUG
import Foundation
import TankbookCore

/// The J9 anomaly UI-test seed (P6.1b): a car with a full year of calm
/// ~5.4 L/100km history and a last-90-days drift to 6.5 L/100km - 21% above
/// the SAME 90 days one year earlier - so `AnomalyEngine.detect` fires with a
/// comfortable margin above the 12% threshold and a seasonally-aligned
/// baseline (never "last month", docs/SCHEMA.md -> ANOMALY). The recent window
/// is still elevated, so the "sustained, not recovering" guard passes too.
/// The middle fills keep the odometer continuous so no absurd cross-gap
/// segment pollutes the headline.
///
/// Numbers, pinned: baseline 43 L / 800 km = 5.375 L/100km; rolling 52 L /
/// 800 km = 6.5 L/100km; magnitude = (6.5 - 5.375) / 5.375 = 0.2093, which
/// renders as "21%". The segment closing exactly at 90 days ago is excluded
/// from the rolling window (strict `>` in `AnomalyEngine`) but included in the
/// headline (`>=`), so the headline shows the same 6.5 the card quotes.
enum AnomalyTestSeed {
    static func seed(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let fills: [HomeTestSeed.FillSpec] = [
            HomeTestSeed.FillSpec(daysAgo: 440, odometer: 110_000, litres: 43,
                                  amount: "70.00", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 420, odometer: 110_800, litres: 43,
                                  amount: "70.00", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 400, odometer: 111_600, litres: 43,
                                  amount: "70.00", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 380, odometer: 112_400, litres: 43,
                                  amount: "70.00", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 300, odometer: 113_200, litres: 43,
                                  amount: "70.00", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 120, odometer: 114_000, litres: 43,
                                  amount: "70.00", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 90, odometer: 114_800, litres: 52,
                                  amount: "84.76", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 60, odometer: 115_600, litres: 52,
                                  amount: "84.76", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 30, odometer: 116_400, litres: 52,
                                  amount: "84.76", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 2, odometer: 117_200, litres: 52,
                                  amount: "84.76", price: "1.630", stationID: nil)
        ]
        for spec in fills {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: vehicle.id, spec))
        }
    }
}
#endif
