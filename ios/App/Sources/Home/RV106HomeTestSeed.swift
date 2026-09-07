#if DEBUG
import Foundation
import TankbookCore

/// RV.106's deterministic Home state (screenshots + L4): the owner's exact
/// report on their imported history. A EUR car holds a converted month (August:
/// every row carries its amount, the divider shows a real total) beside months
/// whose rows are ALL still waiting on a rate (June and July 2026: no row shows
/// an amount and the divider must say why instead of printing `0 €`).
///
/// `-seedHomeRV106Pending` leaves June/July rate-pending. The pending dates are
/// OUTSIDE the bundled rate seed pack (which covers 2026-07-22 .. 08-21), so a
/// plain seeded launch (offline, P6.21) can never fill them - the F9 footnote
/// and the pending dividers hold. `-stubRatesMissThenHit` then supplies the
/// rates on a LATER `/rates/pack` request (the first one answers empty - the
/// server had not published those dates yet), so a user tap on "Check for
/// rates" or a later launch fills them exactly as the owner's would once the
/// archive was published.
enum RV106HomeTestSeed {
    static func seedPending(_ repository: TankbookRepository) {
        seed(repository)
    }

    private static func seed(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository)

        // A converted month this year: August 2026 (the owner's "August rows
        // carry amounts (107.25 €, 101.71 €, 112.06 €)"). Same-currency EUR
        // rows, so nothing can touch them at launch - the divider is complete.
        let august = [
            (month: 8, day: 5, odo: 123_000, amount: "107.25"),
            (month: 8, day: 12, odo: 123_800, amount: "101.71"),
            (month: 8, day: 26, odo: 124_600, amount: "112.06")
        ]
        for row in august {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 0, odometer: row.odo, litres: 42.0,
                                      amount: row.amount, price: "1.630", stationID: shell.id),
                date: day(2026, row.month, row.day)))
        }

        // The pending months: July and June 2026, foreign (PLN) with no rate on
        // the device, dated before the seed pack begins so nothing fills them.
        let pending = [
            (month: 7, day: 3, odo: 121_400, amount: "289.50"),
            (month: 7, day: 18, odo: 122_200, amount: "294.00"),
            (month: 6, day: 7, odo: 119_400, amount: "299.00"),
            (month: 6, day: 21, odo: 120_200, amount: "282.00")
        ]
        for row in pending {
            let money = Money(amount: Decimal(string: row.amount)!,
                              currency: .pln, homeCurrency: .eur)
            try? repository.upsertFillUp(HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: 0, odometer: row.odo, litres: 47.3,
                                      amount: row.amount, price: "6.120", stationID: shell.id),
                date: day(2026, row.month, row.day), money: money))
        }
    }

    /// A fixed calendar day (the bundle seed pack covers 2026-07-22 .. 08-21;
    /// June and early July are deliberately outside it, exactly like
    /// `HomeTestSeed.fixedDay` keeps 08-22..24 outside).
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date()
    }

    private static func makeStation(_ repository: TankbookRepository) -> Station {
        let now = Date()
        let station = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Shell", brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: nil)
        try? repository.upsertStation(station)
        return station
    }
}
#endif
