#if DEBUG
import Foundation
import TankbookCore

/// RV.147's deterministic Trends state (L4 + screenshots): a EUR car whose
/// trailing-90-day window holds converted fills AND rate-pending PLN fills -
/// the shape whose cost-per-km tile used to read a plausible `0.07 €` while
/// four entries were still waiting on a rate.
///
/// `-seedHomeRV147Pending` leaves the window's money inexact: the pending rows
/// are dated RELATIVE to launch (not fixed calendar days) because the 90-day
/// cost window is measured from "now" - a fixed-date seed would age out of the
/// window a few months after it was written and the very state under test would
/// silently disappear. Odometer values are strictly increasing so no F9a
/// conflict fires, and enough full fills close segments that the Trends
/// consumption tile renders beside the withheld cost/km tile - proving the
/// cost/km tile is absent because of the pending rows, not because the car has
/// no data.
enum RV147HomeTestSeed {
    static func seedPending(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository)

        // Three converted EUR fills interleaved with two rate-pending PLN fills,
        // all inside the trailing 90-day window (88 .. 3 days ago). The pending
        // rows carry no home amount yet; the converted ones do.
        for spec in [
            HomeTestSeed.FillSpec(daysAgo: 88, odometer: 118_000, litres: 42.1,
                                  amount: "70.56", price: "1.676", stationID: shell.id),
            HomeTestSeed.FillSpec(daysAgo: 44, odometer: 119_300, litres: 43.0,
                                  amount: "71.17", price: "1.655", stationID: shell.id),
            HomeTestSeed.FillSpec(daysAgo: 3, odometer: 120_600, litres: 41.4,
                                  amount: "68.46", price: "1.630", stationID: shell.id)
        ] {
            try? repository.upsertFillUp(HomeTestSeed.makeFill(vehicleID: vehicle.id, spec))
        }

        for row in [
            (daysAgo: 62, odometer: 118_700, amount: "289.50"),
            (daysAgo: 22, odometer: 119_900, amount: "294.00")
        ] {
            let money = Money(amount: Decimal(string: row.amount)!,
                              currency: .pln, homeCurrency: .eur)
            try? repository.upsertFillUp(HomeTestSeed.makeFill(
                vehicleID: vehicle.id,
                HomeTestSeed.FillSpec(daysAgo: row.daysAgo, odometer: row.odometer,
                                      litres: 47.3, amount: row.amount, price: "6.120",
                                      stationID: shell.id),
                money: money))
        }
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
