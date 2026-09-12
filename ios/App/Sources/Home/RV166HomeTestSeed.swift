#if DEBUG
import Foundation
import TankbookCore

/// RV.166's deterministic Home state (screenshot + L4): the defect shape in one
/// receipt - a purchase group whose known members total 30.00 EUR beside a third
/// line still waiting on a rate. Before the fix the group header printed a bare
/// `30.00 €` that read as the whole receipt; after it, the header prints the
/// known sum with the pending phrase beneath it.
///
/// `-seedHomeRV166PartialGroup` writes one July 2026 purchase group: a converted
/// EUR fill (10.00), a converted EUR wash (20.00) and a rate-pending PLN wash
/// (50.00) from the same slip. The pending line is dated OUTSIDE the bundled
/// rate seed pack (2026-07-22 .. 08-21), exactly like `RV106HomeTestSeed`, so a
/// plain seeded launch (offline, P6.21) can never fill it - the group stays
/// partial and the F9 footnote holds.
enum RV166HomeTestSeed {
    static func seedPartialGroup(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository)

        let groupID = UUID.v7()
        let groupDay = day(2026, 7, 3)

        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 0, odometer: 121_400, litres: 42.0,
                                  amount: "10.00", price: "1.630", stationID: shell.id),
            purchaseGroupID: groupID,
            date: groupDay))

        try? repository.upsertExpense(expense(
            vehicleID: vehicle.id, date: groupDay.addingTimeInterval(-3600),
            amount: "20.00", title: "Car wash", group: groupID))

        // The rate-pending member: PLN into the EUR car, dated before the seed
        // pack begins so nothing fills it at launch.
        try? repository.upsertExpense(expense(
            vehicleID: vehicle.id, date: groupDay.addingTimeInterval(-7200),
            amount: "50.00", title: "Car wash", group: groupID, pending: true))
    }

    private static func expense(vehicleID: UUID, date: Date, amount: String,
                                title: String, group: UUID?,
                                pending: Bool = false) -> Expense {
        let money: Money
        if pending {
            money = Money(amount: Decimal(string: amount)!,
                          currency: .pln, homeCurrency: .eur)
        } else {
            money = Money(amount: Decimal(string: amount)!,
                          currency: .eur, homeCurrency: .eur)
        }
        return Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: nil,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: group,
            category: .other(title), title: title,
            installedInServiceId: nil)
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

    /// A fixed calendar day outside the bundled seed pack (2026-07-22 .. 08-21),
    /// so the pending line cannot fill at launch - RV106's own dating rule.
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date()
    }
}
#endif
