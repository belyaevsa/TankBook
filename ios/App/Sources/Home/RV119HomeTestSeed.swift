#if DEBUG
import Foundation
import TankbookCore

/// RV.119's deterministic Log state: two COMPLETE past calendar months, two
/// full fills each, pinned to the 5th and the 20th of the month before last
/// and the last month (relative to the launch date, so the months are always
/// over and the divider may compare them). The month before last: 100 000 ->
/// 100 600 km, 200 €; last month: 101 000 -> 101 800 km, 150 € - its divider
/// reads 800 km, the two segments closing in it (400 km / 40 L, 800 km / 40 L)
/// 6.7 L/100km, 0.19 €/km, and "25% lower than <the month before last>".
enum RV119HomeTestSeed {
    static func seed(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let calendar = Calendar.current
        let now = Date()
        func pinned(monthsAgo: Int, day: Int) -> Date {
            let month = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = day
            components.hour = 12
            return calendar.date(from: components) ?? month
        }
        func add(monthsAgo: Int, day: Int, odometer: Int, amount: String) {
            let fill = HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 0, odometer: odometer, litres: 40.0,
                                      amount: amount, price: "1.679", stationID: nil),
                date: pinned(monthsAgo: monthsAgo, day: day))
            try? repository.upsertFillUp(fill)
        }
        add(monthsAgo: 2, day: 5, odometer: 100_000, amount: "100.00")
        add(monthsAgo: 2, day: 20, odometer: 100_600, amount: "100.00")
        add(monthsAgo: 1, day: 5, odometer: 101_000, amount: "75.00")
        add(monthsAgo: 1, day: 20, odometer: 101_800, amount: "75.00")
    }
}
#endif
