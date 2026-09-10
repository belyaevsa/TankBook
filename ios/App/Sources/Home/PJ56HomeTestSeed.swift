#if DEBUG
import Foundation
import TankbookCore

/// PJ.56's deterministic Home states (screenshots + L4): the two purchase-group
/// headers that used to say nothing while the month divider over them spoke.
///
/// `-seedHomePJ56PendingGroup` writes one July 2026 purchase group whose THREE
/// members are all still waiting on a rate (PLN into the EUR car, dated outside
/// the bundled rate seed pack of 2026-07-22 .. 08-21 exactly like
/// `RV106HomeTestSeed` / `RV166HomeTestSeed`), so a plain seeded launch
/// (offline, P6.21) can never fill them: the group classifies `.pending`, the
/// month divider says "3 entries pending rates" and - before PJ.56 - the group
/// header stayed blank.
///
/// `-seedHomePJ56MixedGroup` writes one July 2026 purchase group whose known
/// members span home currencies - two EUR rows and one USD row on the EUR car,
/// the shape a member edited after a Garage home change leaves behind (RV.144
/// re-homes only the edited row; its converted siblings keep the old home) - so
/// the group classifies `.mixed` and its header must state the per-currency
/// breakdown, never a summed total (RV.145, hard rule 3).
enum PJ56HomeTestSeed {
    static func seedPendingGroup(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository)

        let groupID = UUID.v7()
        let groupDay = day(2026, 7, 3)

        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 0, odometer: 121_400, litres: 42.0,
                                  amount: "71.02", price: "6.120", stationID: shell.id),
            purchaseGroupID: groupID,
            date: groupDay,
            money: pendingMoney("71.02")))

        try? repository.upsertExpense(expense(
            vehicleID: vehicle.id, date: groupDay.addingTimeInterval(-3600),
            amount: "20.00", title: "Car wash", group: groupID, pending: true))

        try? repository.upsertExpense(expense(
            vehicleID: vehicle.id, date: groupDay.addingTimeInterval(-7200),
            amount: "8.00", title: "Car wash", group: groupID, pending: true))
    }

    static func seedMixedGroup(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository)

        let groupID = UUID.v7()
        let groupDay = day(2026, 7, 3)

        // The EUR rows are known in EUR (home == original, snapshotted at rate
        // 1); the USD row is known in USD - the shape one edited member keeps
        // after a home change while its converted siblings stayed in the old
        // home (docs/ERRORS.md -> Home, PJ.56).
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 0, odometer: 121_400, litres: 42.0,
                                  amount: "71.02", price: "1.679", stationID: shell.id),
            purchaseGroupID: groupID,
            date: groupDay))

        try? repository.upsertExpense(expense(
            vehicleID: vehicle.id, date: groupDay.addingTimeInterval(-3600),
            amount: "20.00", title: "Car wash", group: groupID))

        try? repository.upsertExpense(expense(
            vehicleID: vehicle.id, date: groupDay.addingTimeInterval(-7200),
            amount: "8.00", title: "Car wash", group: groupID, home: .usd))
    }

    private static func pendingMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .pln, homeCurrency: .eur)
    }

    private static func expense(vehicleID: UUID, date: Date, amount: String,
                                title: String, group: UUID?,
                                pending: Bool = false,
                                home: CurrencyCode = .eur) -> Expense {
        let money: Money
        if pending {
            money = Money(amount: Decimal(string: amount)!,
                          currency: .pln, homeCurrency: .eur)
        } else {
            money = Money(amount: Decimal(string: amount)!,
                          currency: home, homeCurrency: home)
        }
        return Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: nil,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: group,
            category: .other(title), title: title, recurrence: nil,
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

    /// A fixed calendar day outside the bundled rate seed pack (2026-07-22 ..
    /// 08-21), so the pending lines cannot fill at launch - RV.106's dating rule.
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date()
    }
}
#endif
