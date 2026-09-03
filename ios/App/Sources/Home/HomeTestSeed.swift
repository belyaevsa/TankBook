#if DEBUG
import Foundation
import TankbookCore

/// UI-test DB seeding for Home (the same hook pattern as `ManualFillUpTestSeed`,
/// and the reason Home's states are deterministic). Each `-seedHome*` argument
/// writes the smallest history that renders that state; combining with
/// `-homeResetDatabase` wipes the app database first so the states are isolated
/// from each other within a test run.
///
/// Real-data states (vehicle presence, entry presence, D4) are seeded here.
/// Everything sync-dependent (S2/S5/S7, reminder banner, guest chrome) is a
/// presentation fixture in `HomePresentables` - no real data exists until P4.
enum HomeTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-seedHome") })
            || arguments.contains("-homeResetDatabase") else { return }

        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        // The J9 anomaly dismissal store is UserDefaults-backed (UserDefaults
        // survive `-homeResetDatabase`, which only wipes the database), so a
        // test that needs the card back resets it explicitly.
        AnomalyInsightStore.resetForTestsIfRequested(arguments)
        guard let repository = try? AppStore.repository() else { return }
        // Idempotent: a seed that has already run (or another test's seed) does
        // not add a second vehicle, so app data survives across launches within
        // a run - matching ManualFillUpTestSeed's contract.
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        if let action = Self.seedAction(for: arguments) {
            action(repository)
        }
    }

    /// Maps the `-seedHome*` launch arguments to their seeding functions. The
    /// lookup is data, not an if/else ladder, so adding a seed keeps the
    /// dispatch simple (swiftlint cyclomatic_complexity).
    private static func seedAction(for arguments: [String]) -> ((TankbookRepository) -> Void)? {
        let actions: [(argument: String, seed: (TankbookRepository) -> Void)] = [
            ("-seedHomeEmptyVehicle", seedEmptyVehicle),
            ("-seedHomeSingleFill", seedSingleFill),
            ("-seedHomeFullHistory", seedFullHistory),
            ("-seedHomeSingleFuelLog", seedSingleFuelLog),
            ("-seedHomeConflict", seedConflict),
            ("-seedHomeEditHistory", seedEditHistory),
            ("-seedHomePendingRates", seedPendingRates),
            ("-seedHomeRV29Foreign", seedForeignConverted),
            ("-seedHomeDuplicate", seedDuplicate),
            ("-seedHomeCarSwitcher", CarSwitcherTestSeed.seedGarage),
            ("-seedHomeCarSwitcherLimit", CarSwitcherTestSeed.seedLimit),
            ("-seedHomeAnomaly", AnomalyTestSeed.seed),
            ("-seedHomeReminderDue", seedReminderDue)
        ]
        return actions.first { arguments.contains($0.argument) }?.seed
    }

    // MARK: - Seeds

    private static func seedEmptyVehicle(_ repository: TankbookRepository) {
        try? repository.upsertVehicle(makeVehicle())
    }

    /// PJ.4: a REAL reminder due inside the attention window (12 days), so the
    /// Home banner derives from actual data - the same shape the `-forceReminderDue`
    /// fixture used to paint ("Insurance renewal due in 12 days"), but a real,
    /// editable, completable row. No launch argument can force the banner
    /// anymore; this seed is what a test (or a screenshot) shows it with.
    private static func seedReminderDue(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let reminder = ReminderLifecycle.makeReminder(
            vehicleId: vehicle.id, title: "Insurance renewal", category: .insurance,
            dueDate: Date().addingTimeInterval(12 * 86_400), dueOdometer: nil,
            recurrence: nil)
        try? repository.upsertReminder(reminder)
    }

    /// The D4 state: a car, one full tank logged, no segment closed yet.
    private static func seedSingleFill(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let fill = makeFill(vehicleID: vehicle.id,
                            FillSpec(daysAgo: 6, odometer: 118_000, litres: 42.3,
                                     amount: "71.02", price: "1.679", stationID: nil))
        try? repository.upsertFillUp(fill)
    }

    /// A five-month history: closed segments, a headline, current-month spend,
    /// last price per litre and a real log stream - month dividers, all four
    /// entry types interleaved, a purchase group (fuel + car wash from one
    /// receipt) and attached receipts on two entries. The "Full" state
    /// (design/screens/HomeA.dc.html).
    private static func seedFullHistory(_ repository: TankbookRepository) {
        // A realistic multi-fuel car (petrol + LPG, docs/SCHEMA.md): the D4
        // "Full" state must show the conditional fuel-kind badge on the log
        // rows, and the car's fills are 95, so the badge reads "95".
        let vehicle = makeVehicle(fuelKinds: [.petrol95, .lpg])
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository, name: "Shell")
        let neste = makeStation(repository, name: "Neste")

        // Two receipts: one shared by the purchase group (fuel + car wash from
        // the same slip), one for the Ionity charge.
        let groupReceipt = makeAttachment(repository)
        let ionityReceipt = makeAttachment(repository)
        let groupID = UUID.v7()

        let groupFillDate = Date().addingTimeInterval(-2 * 86_400)
        let fills: [FillUp] = [
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 150, odometer: 118_000, litres: 42.1,
                              amount: "70.56", price: "1.676", stationID: shell.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 120, odometer: 118_800, litres: 41.4,
                              amount: "69.14", price: "1.670", stationID: neste.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 90, odometer: 119_600, litres: 43.0,
                              amount: "71.17", price: "1.655", stationID: shell.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 60, odometer: 120_400, litres: 40.6,
                              amount: "66.18", price: "1.630", stationID: neste.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 30, odometer: 121_200, litres: 42.8,
                              amount: "69.90", price: "1.633", stationID: shell.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 7, odometer: 122_000, litres: 41.2,
                              amount: "66.90", price: "1.624", stationID: neste.id)),
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 2, odometer: 122_800, litres: 43.5,
                              amount: "71.02", price: "1.633", stationID: shell.id),
                     purchaseGroupID: groupID, attachments: [groupReceipt.id],
                     date: groupFillDate),
            // A fill today guarantees current-month spend exists on any run
            // date, so the "Full" state always renders the month-spend vital.
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 0, odometer: 123_600, litres: 42.0,
                              amount: "68.46", price: "1.630", stationID: neste.id))
        ]
        for fill in fills {
            try? repository.upsertFillUp(fill)
        }

        // The rest of the stream: a charge, a service, and two expenses. One
        // expense (the car wash) belongs to the fill's purchase group.
        try? repository.upsertChargeSession(makeCharge(
            vehicleID: vehicle.id,
            ChargeSpec(daysAgo: 5, odometer: 122_400, energyKWh: 38,
                       amount: "21.50", provider: "Ionity"),
            attachments: [ionityReceipt.id]))

        let serviceDate = Date().addingTimeInterval(-9 * 86_400)
        try? repository.upsertServiceRecord(makeService(
            vehicleID: vehicle.id, date: serviceDate, odometer: 121_800,
            amount: "148.00", vendor: "Bosch Service"))

        let parkingDate = Date().addingTimeInterval(-12 * 86_400)
        try? repository.upsertExpense(makeExpense(
            vehicleID: vehicle.id, date: parkingDate, odometer: 121_500,
            amount: "6.00", title: "Parking"))

        let washDate = groupFillDate.addingTimeInterval(-3600)
        try? repository.upsertExpense(makeExpense(
            vehicleID: vehicle.id, date: washDate, odometer: nil,
            amount: "8.00", title: "Car wash",
            purchaseGroupID: groupID, attachments: [groupReceipt.id]))
    }

    /// A single-fuel car's log: the fuel kind is the car's usual one, so no
    /// row prints it (docs/DESIGN.md - the fuel-kind rule, conditional).
    private static func seedSingleFuelLog(_ repository: TankbookRepository) {
        let vehicle = makeVehicle(fuelKinds: [.petrol95])
        try? repository.upsertVehicle(vehicle)
        let neste = makeStation(repository, name: "Neste")
        for spec in [
            FillSpec(daysAgo: 75, odometer: 118_000, litres: 42.0,
                     amount: "68.40", price: "1.629", stationID: neste.id),
            FillSpec(daysAgo: 40, odometer: 118_800, litres: 41.5,
                     amount: "67.90", price: "1.636", stationID: neste.id),
            FillSpec(daysAgo: 5, odometer: 119_600, litres: 42.3,
                     amount: "69.30", price: "1.638", stationID: neste.id)
        ] {
            try? repository.upsertFillUp(makeFill(vehicleID: vehicle.id, spec))
        }
    }

    /// The F9a/S3 conflict state: a fill whose odometer breaks the timeline, so
    /// Home shows the amber badge and the "1 entry excluded" footnote.
    private static func seedConflict(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let flagged = makeFill(
            vehicleID: vehicle.id,
            FillSpec(daysAgo: 2, odometer: 117_900, litres: 43.5,
                     amount: "71.02", price: "1.633", stationID: nil),
            conflict: .flagged(kind: .order, detectedAt: Date()))
        try? repository.upsertFillUp(flagged)
        try? repository.upsertFillUp(
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 15, odometer: 118_500, litres: 41.2,
                              amount: "66.90", price: "1.624", stationID: nil)))
        try? repository.upsertFillUp(
            makeFill(vehicleID: vehicle.id,
                     FillSpec(daysAgo: 30, odometer: 118_000, litres: 42.8,
                              amount: "69.90", price: "1.633", stationID: nil)))
    }

    /// The S2 duplicate state (docs/SYNC.md): one physical fill logged twice at
    /// the same station - dates within 30 minutes, volumes within 5% - so the
    /// heuristic flags the pair and Home renders the combined card. This is the
    /// state a sync-arrived duplicate would land in too (two records for one
    /// fill-up); until P4 it is seeded like every other real-data state. The
    /// card must render regardless of which pair member the detector counts.
    private static func seedDuplicate(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository, name: "Shell")
        let firstDate = Date().addingTimeInterval(-2 * 86_400)
        try? repository.upsertFillUp(makeFill(
            vehicleID: vehicle.id,
            FillSpec(daysAgo: 2, odometer: 122_800, litres: 42.3,
                     amount: "71.02", price: "1.679", stationID: shell.id),
            date: firstDate))
        try? repository.upsertFillUp(makeFill(
            vehicleID: vehicle.id,
            FillSpec(daysAgo: 2, odometer: 122_800, litres: 42.9,
                     amount: "72.05", price: "1.679", stationID: shell.id),
            date: firstDate.addingTimeInterval(15 * 60)))
    }

    /// The golden D1 series (docs/fixtures/consumption-golden.json): eight full
    /// fills over ~15 weeks, so the headline is the documented 6.9 and an edit
    /// to the newest fill's odometer moves it to a known value. The Edit entry
    /// UI tests drive the delta toast and the save-anyway flag against this.
    private static func seedEditHistory(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        for spec in [
            FillSpec(daysAgo: 98, odometer: 114_980, litres: 45.9,
                     amount: "77.02", price: "1.678", stationID: nil),
            FillSpec(daysAgo: 84, odometer: 115_622, litres: 44.6,
                     amount: "74.51", price: "1.671", stationID: nil),
            FillSpec(daysAgo: 70, odometer: 116_281, litres: 46.8,
                     amount: "77.99", price: "1.667", stationID: nil),
            FillSpec(daysAgo: 56, odometer: 116_904, litres: 43.1,
                     amount: "71.62", price: "1.662", stationID: nil),
            FillSpec(daysAgo: 42, odometer: 117_561, litres: 45.5,
                     amount: "75.30", price: "1.655", stationID: nil),
            FillSpec(daysAgo: 28, odometer: 118_207, litres: 44.2,
                     amount: "72.96", price: "1.651", stationID: nil),
            FillSpec(daysAgo: 14, odometer: 118_843, litres: 43.9,
                     amount: "72.42", price: "1.650", stationID: nil),
            FillSpec(daysAgo: 1, odometer: 119_486, litres: 42.3,
                     amount: "71.02", price: "1.679", stationID: nil)
        ] {
            try? repository.upsertFillUp(makeFill(vehicleID: vehicle.id, spec))
        }
    }

    // MARK: - RV.29: a foreign price on a home-currency car

    /// The RV.29 lie made visible, then fixed: a RUB-home car whose most recent
    /// fill was paid in EUR. The EUR fill carries its conversion snapshot
    /// (immutable, hard rule 3), so the Home price tile renders the CONVERTED
    /// home price with the home symbol (`168.333 ₽`), never the raw `1.919` the
    /// old code stamped `₽` on - and the log rows show their converted home
    /// amounts the same way. Screenshot seed: it exists so the fix has a visual
    /// record, not because the state is exotic.
    private static func seedForeignConverted(_ repository: TankbookRepository) {
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Škoda Octavia", make: "Škoda", model: "Octavia", year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 50, batteryCapacityKWh: nil, homeCurrency: .rub,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
        try? repository.upsertVehicle(vehicle)

        for spec in [
            FillSpec(daysAgo: 34, odometer: 118_400, litres: 40.0,
                     amount: "2336.00", price: "58.40", stationID: nil),
            FillSpec(daysAgo: 18, odometer: 118_900, litres: 41.5,
                     amount: "2402.85", price: "57.90", stationID: nil)
        ] {
            let money = Money(amount: Decimal(string: spec.amount)!,
                              currency: .rub, homeCurrency: .rub)
            try? repository.upsertFillUp(makeFill(vehicleID: vehicle.id, spec, money: money))
        }

        // The most recent fill is foreign and CONVERTED (its snapshot rate 0.0114
        // EUR/RUB ~ 87.7 RUB/EUR rides with it; the price tile must show the
        // home figure, never the raw EUR number).
        let foreignDate = Date().addingTimeInterval(-3 * 86_400)
        let eurFill = Money(amount: Decimal(string: "76.76")!, currency: .eur, homeCurrency: .rub)
            .converted(using: RateSnapshot(rate: Decimal(string: "0.0114")!,
                                           rateDate: foreignDate, source: .ecb))
        try? repository.upsertFillUp(makeFill(
            vehicleID: vehicle.id,
            FillSpec(daysAgo: 3, odometer: 119_300, litres: 40.0,
                     amount: "76.76", price: "1.919", stationID: nil),
            date: foreignDate, money: eurFill))
    }

    // MARK: - Fixture builders

    /// Shared with `TrendsTestSeed` (same fixture shapes, one source). The
    /// default is a single-kind petrol car - a car that burns two fuels that
    /// cannot share a tank does not exist, so the old `[.petrol95, .diesel]`
    /// default is gone; callers wanting a multi-fuel car pass a realistic pair
    /// (`seedFullHistory` uses petrol + LPG).
    static func makeVehicle(fuelKinds: [FuelKind] = [.petrol95]) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: fuelKinds,
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    /// The F9 pending-rates state (docs/JOURNEYS.md F9): a log where three
    /// foreign fill-ups are still waiting on a rate. They are dated OUTSIDE the
    /// bundled rate seed pack (2026-08-22..24; the pack ends 08-21) so the
    /// bundled seed alone CANNOT fill them - the "N entries pending rates"
    /// footnote shows until a rate arrives for those days. `-stubRates` supplies
    /// those rates through the launch refresh -> S8 backfill (PJ.8), so the
    /// same seed renders both sides of the transition WITHOUT `-runRateBackfill`.
    /// A converted EUR history keeps the log realistic (three converted rows
    /// with amounts, three pending PLN rows without). Odometer values are
    /// strictly increasing so no F9a conflict fires.
    private static func seedPendingRates(_ repository: TankbookRepository) {
        let vehicle = makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository, name: "Shell")
        for spec in [
            FillSpec(daysAgo: 90, odometer: 118_000, litres: 42.1,
                     amount: "70.56", price: "1.676", stationID: shell.id),
            FillSpec(daysAgo: 60, odometer: 118_800, litres: 41.4,
                     amount: "69.14", price: "1.670", stationID: shell.id),
            FillSpec(daysAgo: 30, odometer: 119_600, litres: 43.0,
                     amount: "71.17", price: "1.655", stationID: shell.id)
        ] {
            try? repository.upsertFillUp(makeFill(vehicleID: vehicle.id, spec))
        }
        let pending = [
            (day: fixedDay(2026, 8, 22), odometer: 120_000, amount: "289.50"),
            (day: fixedDay(2026, 8, 23), odometer: 120_800, amount: "294.00"),
            (day: fixedDay(2026, 8, 24), odometer: 121_600, amount: "299.00")
        ]
        for row in pending {
            let money = Money(amount: Decimal(string: row.amount)!,
                              currency: .pln, homeCurrency: .eur)
            try? repository.upsertFillUp(makeFill(
                vehicleID: vehicle.id,
                FillSpec(daysAgo: 0, odometer: row.odometer, litres: 47.3,
                         amount: row.amount, price: "6.120", stationID: shell.id),
                date: row.day, money: money))
        }
    }

    /// A fixed calendar day (the bundled rate seed pack covers 2026-07-22 ..
    /// 2026-08-21; a relative "days ago" date drifts with the run date and can
    /// fall outside it, which would make a backfill fill nothing).
    private static func fixedDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date()
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

    private static func makeAttachment(_ repository: TankbookRepository) -> Attachment {
        let now = Date()
        let attachment = Attachment(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: UUID().uuidString,
                                             relativePath: "seed/\(UUID().uuidString).jpg"),
            extractedTimestamp: nil, ocrText: nil)
        try? repository.upsertAttachment(attachment)
        return attachment
    }

    /// A fixture fill's data, kept apart from the construction call so the
    /// builder stays small (swiftlint function_parameter_count). Shared with
    /// `TrendsTestSeed`.
    struct FillSpec {
        let daysAgo: Int
        let odometer: Int
        let litres: Double
        let amount: String
        let price: String
        let stationID: UUID?
    }

    static func makeFill(vehicleID: UUID, _ spec: FillSpec,
                         conflict: ConflictState = .none,
                         purchaseGroupID: UUID? = nil,
                         attachments: [AttachmentID] = [],
                         date: Date? = nil,
                         money: Money? = nil) -> FillUp {
        let fillDate = date ?? Date().addingTimeInterval(-Double(spec.daysAgo) * 86_400)
        return FillUp(
            id: UUID.v7(), createdAt: fillDate, updatedAt: fillDate, deletedAt: nil,
            vehicleId: vehicleID, date: fillDate, odometer: spec.odometer,
            money: money ?? Money(amount: Decimal(string: spec.amount)!,
                                  currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual,
            conflict: conflict, purchaseGroupId: purchaseGroupID,
            volumeL: spec.litres, unitPrice: Decimal(string: spec.price)!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: spec.stationID, crossCheck: .verified, extraction: nil)
    }

    /// A fixture charge's data, kept apart from the construction call (the
    /// same swiftlint function_parameter_count discipline as FillSpec). Shared
    /// with `CarSwitcherTestSeed`.
    struct ChargeSpec {
        let daysAgo: Int
        let odometer: Int
        let energyKWh: Double
        let amount: String
        let provider: String
    }

    static func makeCharge(vehicleID: UUID, _ spec: ChargeSpec,
                           attachments: [AttachmentID] = []) -> ChargeSession {
        let date = Date().addingTimeInterval(-Double(spec.daysAgo) * 86_400)
        return ChargeSession(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: spec.odometer,
            money: Money(amount: Decimal(string: spec.amount)!,
                         currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            energyKWh: spec.energyKWh, unitPrice: nil, chargeType: .dcPublic,
            provider: spec.provider, tariffId: nil, durationMin: nil,
            socStartPct: nil, socEndPct: nil, extraction: nil)
    }

    private static func makeService(vehicleID: UUID, date: Date, odometer: Int,
                                    amount: String, vendor: String) -> ServiceRecord {
        ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odometer,
            money: Money(amount: Decimal(string: amount)!,
                         currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            vendor: vendor, items: [], usedParts: [], tireSetId: nil,
            proposedReminderId: nil)
    }

    private static func makeExpense(vehicleID: UUID, date: Date, odometer: Int?,
                                    amount: String, title: String,
                                    purchaseGroupID: UUID? = nil,
                                    attachments: [AttachmentID] = []) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odometer,
            money: Money(amount: Decimal(string: amount)!,
                         currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual,
            conflict: .none, purchaseGroupId: purchaseGroupID,
            category: .other(title), title: title, recurrence: nil,
            installedInServiceId: nil)
    }
}
#endif
