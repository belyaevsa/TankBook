#if DEBUG
import Foundation
import TankbookCore

/// RV.111's deterministic Home state (screenshots + L4): the multi-year import
/// case the row exists for. A EUR car holds a converted month (this month,
/// fixed-day rows that can never cross a month boundary) beside old 2015 rows
/// whose rates are still pending - deliberately OUTSIDE the rolling 400-day
/// pack window, so neither the launch refresh (rolling only) nor the old
/// "Check for rates" (a second rolling refresh) could ever reach them.
///
/// `-seedHomeRV111OldPending` leaves the 2015 rows rate-pending.
/// `-stubRatesEmpty` answers every `/rates/pack` request with an EMPTY pack -
/// the provider reached with no row for those dates (the genuinely-unavailable
/// archive shape, docs/SCHEMA.md -> Exchange rates) - so a "Check for rates"
/// demand drain leaves them pending and the F9 footnote flips to the dead-end
/// manual-rate copy. `-runRateDemandDrain` fires that one demand pass a beat
/// after launch so a screenshot can show the dead end deterministically.
enum RV111HomeTestSeed {
    static func seedPending(_ repository: TankbookRepository) {
        seed(repository)
    }

    private static func seed(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        // A converted month this month (pinned to the 1st, RV.43: a relative
        // date drifts across the month boundary and the spend tile silently
        // vanishes), so the car looks ordinary and the log has context.
        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        for (index, spec) in [
            HomeTestSeed.FillSpec(daysAgo: 0, odometer: 123_000, litres: 42.0,
                                  amount: "70.56", price: "1.630", stationID: nil),
            HomeTestSeed.FillSpec(daysAgo: 0, odometer: 123_800, litres: 41.4,
                                  amount: "69.14", price: "1.670", stationID: nil)
        ].enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: index, to: monthStart) ?? monthStart
            try? repository.upsertFillUp(HomeTestSeed.makeFill(
                vehicleID: vehicle.id, spec, date: date))
        }

        // The old pending rows: 2015 PLN fills with no rate on the device, dated
        // years before the rolling pack window. Two rows - the "2 entries
        // pending rates" footnote.
        let pending = [
            (day: day(2015, 6, 4), odometer: 60_000, amount: "289.50"),
            (day: day(2015, 6, 21), odometer: 60_800, amount: "294.00")
        ]
        for row in pending {
            let money = Money(amount: Decimal(string: row.amount)!,
                              currency: .pln, homeCurrency: .eur)
            try? repository.upsertFillUp(HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 0, odometer: row.odometer, litres: 47.3,
                                      amount: row.amount, price: "6.120", stationID: nil),
                date: row.day, money: money))
        }
    }

    private static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))
            ?? Date()
    }
}
#endif
