#if DEBUG
import Foundation
import TankbookCore

/// RV.88's deterministic Home states (screenshots): the owner's exact report,
/// before and after the drain. A EUR car holds two USD rows that an import just
/// wrote (provenance `.import`, foreign money with no rate on the device).
///
/// `-seedHomeRV88USDPending` leaves them rate-pending: Home shows "0 €" for the
/// current month beside the "N entries pending rates" footnote - the defect.
/// `-seedHomeRV88USDConverted` writes the SAME rows already drained (each at its
/// OWN `rateDate`, rate 1.10, so 110 USD = 100.00 EUR - hard rule 3): the month
/// total is real and the footnote is gone - the fix. Two frames of one state, so
/// the screenshot pair reads as a transition without relying on the async drain.
enum RV88HomeTestSeed {
    static func seedPending(_ repository: TankbookRepository) {
        seed(repository, converted: false)
    }

    static func seedConverted(_ repository: TankbookRepository) {
        seed(repository, converted: true)
    }

    private static func seed(_ repository: TankbookRepository, converted: Bool) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)

        // Two fills in the current month (yesterday + today), so the current-
        // month spend tile and the month divider are the surface under test.
        // On the 1st of a month yesterday falls in the previous month and only
        // today's fill anchors the current-month tile - still one converted (or
        // pending) row, so the frame stays meaningful every day of the month.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let shell = makeStation(repository)
        for (date, odometer, amount) in [
            (yesterday, 119_100, "110.00"),
            (today, 119_700, "110.00")
        ] {
            let base = Money(amount: Decimal(string: amount)!,
                             currency: .usd, homeCurrency: .eur)
            let money = converted
                ? base.converted(using: RateSnapshot(rate: Decimal(string: "1.10")!,
                                                     rateDate: date, source: .ecb))
                : base
            try? repository.upsertFillUp(FillUp(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: odometer,
                money: money, note: nil, attachments: [],
                provenance: .import(source: "mfm"), conflict: .none,
                purchaseGroupId: nil, volumeL: 42.5, unitPrice: nil,
                fuelKind: .petrol95, fuelGrade: nil, isFull: true,
                tankLevelAfterPct: 100, stationId: shell.id,
                crossCheck: .notApplicable, extraction: nil))
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
