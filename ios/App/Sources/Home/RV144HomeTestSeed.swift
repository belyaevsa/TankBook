#if DEBUG
import Foundation
import TankbookCore

/// RV.144's deterministic states (L4 + screenshots): a car whose Garage home
/// currency changed since an entry was written, so the entry's `Money` pair
/// still records the OLD home currency.
///
/// `-seedHomeRV144Edit` writes the L4 scene: a PLN-home car holding one plain
/// PLN fill and one fill the import wrote while the home was EUR - its money
/// pair is `{ EUR, homeCurrency: EUR }`, snapshotted at rate 1 - dated outside
/// the bundled rate seed pack so a backfill can never quietly resolve it. The
/// UI test opens that fill and edits its currency to PLN (the current home): a
/// fixed build re-homes and snapshots it at rate 1; the broken build leaves it
/// rate-pending asking for a rate into the stale EUR.
///
/// `-seedHomeRV144Resolved` writes the owner's end state for screenshots: the
/// edited fill as the fix leaves it - currency USD, `homeCurrency: USD`, rate
/// 1, the amount as paid - so the Edit-entry sheet renders the resolved row in
/// the car's own dollars.
enum RV144HomeTestSeed {
    /// The Home-load hook (RV.76/ReminderTestSeed pattern): the RV.144 states
    /// are launched by two arguments (`-seedHomeRV144Edit`, the L4 driving
    /// state; `-seedHomeRV144Resolved`, the screenshot state), both sharing the
    /// once-per-launch `-homeResetDatabase` reset that HomeTestSeed runs. This
    /// hook lives separately because HomeTestSeed's dispatch enum is at its
    /// lint body-length ceiling; the seeds are idempotent like every other.
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let edit = arguments.contains("-seedHomeRV144Edit")
        let resolved = arguments.contains("-seedHomeRV144Resolved")
        guard edit || resolved else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }
        if edit {
            seedEditHomeCurrency(repository)
        } else {
            seedResolved(repository)
        }
    }

    static func seedEditHomeCurrency(_ repository: TankbookRepository) {
        let vehicle = makeVehicle(name: "Volvo V60", homeCurrency: .pln)
        try? repository.upsertVehicle(vehicle)

        // A plain home-currency fill anchors the timeline (older, lower
        // odometer) so the edited fill has a valid delta.
        let prior = fixedDay(2026, 8, 20)
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: prior, updatedAt: prior, deletedAt: nil,
            vehicleId: vehicle.id, date: prior, odometer: 118_579,
            money: Money(amount: Decimal(string: "70.15")!, currency: .pln, homeCurrency: .pln),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.1, unitPrice: Decimal(string: "1.666")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil))

        // The fill the import wrote while the car's home was EUR: the money
        // pair's homeCurrency is the stale EUR, not the car's current PLN. Its
        // date (2026-08-28) is outside the bundled rate pack (ends 08-21), so
        // nothing can silently backfill it - the L4 assertion sees exactly the
        // state the edit produced.
        let target = fixedDay(2026, 8, 28)
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: target, updatedAt: target, deletedAt: nil,
            vehicleId: vehicle.id, date: target, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .import(source: "mfm"), conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil))
    }

    static func seedResolved(_ repository: TankbookRepository) {
        let vehicle = makeVehicle(name: "Volvo V60", homeCurrency: .usd)
        try? repository.upsertVehicle(vehicle)

        // An older row the import wrote while the home was EUR stays EUR - hard
        // rule 3: its snapshot was true when recorded. It is the context that
        // makes the resolved row below mean something.
        let older = fixedDay(2026, 8, 20)
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: older, updatedAt: older, deletedAt: nil,
            vehicleId: vehicle.id, date: older, odometer: 118_579,
            money: Money(amount: Decimal(string: "36.06")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .import(source: "mfm"), conflict: .none,
            purchaseGroupId: nil, volumeL: 21.5, unitPrice: Decimal(string: "1.677")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil))

        // The owner's edited fill after a resolved currency edit: currency USD,
        // re-homed to the car's USD, snapshotted at rate 1 - the row the fix
        // produces the moment the edit saves, with no rate and no fetch.
        let edited = fixedDay(2026, 8, 28)
        try? repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: edited, updatedAt: edited, deletedAt: nil,
            vehicleId: vehicle.id, date: edited, odometer: 119_486,
            money: Money(amount: Decimal(string: "2101.75")!, currency: .usd, homeCurrency: .usd),
            note: nil, attachments: [], provenance: .import(source: "mfm"), conflict: .none,
            purchaseGroupId: nil, volumeL: 60.05, unitPrice: Decimal(string: "35.00")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil))
    }

    private static func makeVehicle(name: String, homeCurrency: CurrencyCode) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, make: "Volvo", model: "V60", year: 2015, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: homeCurrency,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fixedDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date()
    }
}
#endif
