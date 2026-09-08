#if DEBUG
import Foundation
import TankbookCore

/// RV.145's deterministic Home states (L4 + screenshots): a car whose home
/// currency changed AFTER rows were converted, so a USD car holds EUR-homed
/// rows - the owner's 2026-09-08 scene - plus genuinely mixed months.
///
/// `-seedHomeRV145Owner` is the owner's exact report: a USD car whose current
/// month rows are EUR-homed (converted while the car's home was EUR; the stamp
/// survives the Garage change, docs/SCHEMA.md -> Money) beside PLN rows still
/// rate-pending into USD. Before RV.145 the divider summed the euros and
/// stamped the car's `$` on them - `91 $` above `36.06 €` rows.
///
/// `-seedHomeRV145Mixed` adds a USD-homed converted row to the same month, so
/// the month's KNOWN figures span two home currencies and the divider must
/// print the per-currency breakdown - never a bare cross-currency number.
enum RV145HomeTestSeed {
    static func seedOwner(_ repository: TankbookRepository) {
        seed(repository, mixed: false)
    }

    static func seedMixed(_ repository: TankbookRepository) {
        seed(repository, mixed: true)
    }

    private static func seed(_ repository: TankbookRepository, mixed: Bool) {
        let vehicle = makeUSDHomeVehicle()
        try? repository.upsertVehicle(vehicle)

        // Rows are pinned to TODAY and the preceding days (like RV.88's seed) so
        // the newest whole month - the divider and the vitals tile under test -
        // is the current one on any day of the month; the two "today" rows sit
        // 11 hours apart (never within the S2 30-minute window) so the
        // duplicate detector cannot pair them.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ ago: Int, _ hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -ago, to: today) ?? today
            return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        }

        // The EUR-homed rows: converted while the car's home was EUR (rate 1,
        // same-currency stamp), 36.06 + 28.78 + 26.59 = 91.43. The stamp is the
        // point: `money.homeCurrency` is EUR on a car whose home is now USD.
        let eurRows = [
            (date: day(2, 9), odo: 119_900, amount: "26.59"),
            (date: day(1, 9), odo: 120_600, amount: "28.78"),
            (date: day(0, 8), odo: 121_300, amount: "36.06")
        ]
        for row in eurRows {
            let money = Money(amount: Decimal(string: row.amount)!,
                              currency: .eur, homeCurrency: .eur)
            try? repository.upsertFillUp(fill(vehicleID: vehicle.id, date: row.date,
                                              odometer: row.odo, money: money, volumeL: 42.0))
        }

        if mixed {
            // A USD-homed converted row (recorded since the car moved to USD):
            // the month's known figures now span EUR and USD.
            let money = Money(amount: Decimal(string: "45.60")!,
                              currency: .usd, homeCurrency: .usd)
            try? repository.upsertFillUp(fill(vehicleID: vehicle.id, date: day(0, 19),
                                              odometer: 122_000, money: money, volumeL: 38.4))
        }

        // PLN rows still rate-pending into USD (foreign fills whose rate has
        // not arrived - the F9 state). They contribute no home figure, only the
        // pending count; on the owner's screenshot they sat under the divider.
        let pending = [
            (date: day(4, 9), odo: 118_500, amount: "299.00"),
            (date: day(3, 9), odo: 119_200, amount: "294.00"),
            (date: day(0, 20), odo: 122_800, amount: "289.50")
        ]
        for row in pending {
            let money = Money(amount: Decimal(string: row.amount)!,
                              currency: .pln, homeCurrency: .usd)
            try? repository.upsertFillUp(fill(vehicleID: vehicle.id, date: row.date,
                                              odometer: row.odo, money: money, volumeL: 47.3))
        }
    }

    private static func makeUSDHomeVehicle() -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .usd,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(vehicleID: UUID, date: Date, odometer: Int, money: Money,
                             volumeL: Double) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odometer,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: volumeL, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }
}
#endif
