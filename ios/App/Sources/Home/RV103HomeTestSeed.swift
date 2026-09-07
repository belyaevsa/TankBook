#if DEBUG
import Foundation
import TankbookCore

// RV.103 - seeding for the load-more reveal.
//
// Two states:
// - `-seedHomeRV103LongLog`: the real committed MFM fixture volume - one car
//   (AUDI A4, 364 fill-ups over 2013-2026) so a screenshot of the Log shows the
//   affordance against a genuinely long history, not a synthetic handful.
// - `-seedHomeRV103Reveal`: a compact deterministic history (6 months x 4
//   fills, newest first, oldest month at a unique station) so the L4 test can
//   assert that tapping the affordance reveals a SPECIFIC previously hidden row.
enum RV103HomeTestSeed {

    static func seedLongLog(_ repository: TankbookRepository) {
        // The MFM rows are USD; the car's home currency must match so every row
        // has an immediate home amount (no RV.106 pending-rate noise over the
        // whole decade).
        var vehicle = HomeTestSeed.makeVehicle(fuelKinds: [.diesel])
        vehicle.homeCurrency = .usd
        vehicle.name = "Audi A4"
        try? repository.upsertVehicle(vehicle)
        seedMFMRows(into: repository, vehicleID: vehicle.id)
    }

    /// Reads the committed MFM fuel rows (AUDI A4, monotonic odometer, real
    /// dates and amounts) from the bundled resource and writes them as fill-ups
    /// - the same volume the fixture carries, so Home's reveal sees a real
    /// decade of history.
    static func seedMFMRows(into repository: TankbookRepository, vehicleID: UUID) {
        guard let url = Bundle.main.url(forResource: "import-rv103-fuel", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        // The fixture dates are ISO-8601 strings; the default JSON strategy
        // expects seconds-since-reference and would silently throw, leaving a
        // car with no rows - the exact "long log" this seed exists to create.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let rows = try? decoder.decode([MFMRow].self, from: data) else { return }
        let shell = makeStation(repository, name: "Shell")
        for row in rows {
            let money = Money(amount: Decimal(string: row.amount)!, currency: .usd,
                              homeCurrency: .usd)
            try? repository.upsertFillUp(FillUp(
                id: UUID.v7(), createdAt: row.date, updatedAt: row.date, deletedAt: nil,
                vehicleId: vehicleID, date: row.date, odometer: row.odometer,
                money: money, note: nil, attachments: [],
                provenance: .import(source: "mfm"), conflict: .none,
                purchaseGroupId: nil, volumeL: row.litres, unitPrice: nil,
                fuelKind: .diesel, fuelGrade: nil, isFull: true,
                tankLevelAfterPct: 100, stationId: shell.id,
                crossCheck: .notApplicable, extraction: nil))
        }
    }

    /// Six months x four fills: 24 entries across 6 whole months. The newest
    /// whole months covering ~20 rows are the first ~5 months; the sixth month
    /// (station "Puma") is hidden behind the affordance until the reveal.
    /// Odometer rises with time (older month = lower reading) so no F9a order
    /// flag fires and the reveal stays the only thing under test.
    static func seedRevealHistory(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let newest = makeStation(repository, name: "Neste")
        let older = makeStation(repository, name: "Shell")
        let oldest = makeStation(repository, name: "Puma")
        let stations = [newest, older, oldest]
        let calendar = Calendar.current
        // Anchor to the PREVIOUS month, not the current one: every seeded row
        // must sit in the past on any run date (day 6/13/20/27 of the current
        // month are in the future before the 6th), so the reveal is all the
        // L4 test or a screenshot sees - never a future-dated fill.
        guard let thisMonth = calendar.dateInterval(of: .month, for: Date())?.start,
              let anchor = calendar.date(byAdding: .month, value: -1, to: thisMonth) else { return }
        // Older months sit lower on the odometer: month 0 (newest) is highest.
        var odo = 118_000
        for monthIndex in stride(from: 5, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -monthIndex,
                                                 to: anchor) else { continue }
            // The oldest month (5) uses the unique "Puma" station so the L4 test
            // can assert a SPECIFIC hidden row appears; others alternate.
            let station = monthIndex == 5
                ? oldest
                : (monthIndex.isMultiple(of: 2) ? newest : older)
            for day in [6, 13, 20, 27] {
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                    continue
                }
                odo += 412
                let fill = HomeTestSeed.makeFill(
                    vehicleID: vehicle.id,
                    HomeTestSeed.FillSpec(daysAgo: 0, odometer: odo, litres: 42.3,
                                          amount: String(format: "%.2f", 68.0 + Double(monthIndex)),
                                          price: "1.630", stationID: station.id),
                    date: date)
                try? repository.upsertFillUp(fill)
            }
        }
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

/// A row of the committed MFM fuel fixture, kept to the fields a fill-up seed
/// needs (date, odometer, litres, amount).
struct MFMRow: Decodable {
    let date: Date
    let odometer: Int
    let litres: Double
    let amount: String
}
#endif
