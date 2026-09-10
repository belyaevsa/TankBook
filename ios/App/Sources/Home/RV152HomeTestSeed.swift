#if DEBUG
import Foundation
import TankbookCore

/// RV.152's deterministic state: a EUR-home car whose log is entirely
/// snapshotted EUR rows, so a home-currency change to USD has a real history
/// to restate - the prompt the row is about.
///
/// The dates are fixed and chosen against the bundled rate seed pack
/// (`Rates.seed.json`, EUR-based, 2026-07-22 .. 2026-08-21): two fills fall
/// INSIDE the pack window and resolve at their own date, one falls outside it
/// and stays rate-pending. That makes "Convert the log" a partial convert
/// (2 converted, 1 pending) - the honest case the prompt must state upfront -
/// and makes it visibly different from "Keep the entries as they are", which
/// leaves all three snapshotted rows byte-identical.
enum RV152HomeTestSeed {
    static func seed(_ repository: TankbookRepository) {
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
        try? repository.upsertVehicle(vehicle)

        // Two fills inside the bundled pack window (EUR -> USD resolves) and
        // one outside it (no rate: the convert leaves it pending and counted).
        let rows: [(day: Date, odometer: Int)] = [
            (fixedDay(2026, 8, 10), 118_500),
            (fixedDay(2026, 8, 11), 119_000),
            (fixedDay(2026, 9, 5), 119_500)
        ]
        for (index, row) in rows.enumerated() {
            let amount = Decimal(70 + index)
            try? repository.upsertFillUp(FillUp(
                id: UUID.v7(), createdAt: row.day, updatedAt: row.day, deletedAt: nil,
                vehicleId: vehicle.id, date: row.day, odometer: row.odometer,
                money: Money(amount: amount, currency: .eur, homeCurrency: .eur),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, volumeL: 42.0, unitPrice: nil,
                fuelKind: .petrol95, fuelGrade: nil, isFull: true,
                tankLevelAfterPct: 100, stationId: nil,
                crossCheck: .notApplicable, extraction: nil))
        }
    }

    private static func fixedDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date()
    }
}
#endif
