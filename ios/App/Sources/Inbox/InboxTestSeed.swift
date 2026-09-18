#if DEBUG
import Foundation
import TankbookCore

/// UI-test and screenshot seeding for the inbox (RV.38, RV.45, RV.201).
///
/// Five seeds, each idempotent (once a vehicle exists it no-ops) under the same
/// `-homeResetDatabase` gate:
///
/// - `-seedInboxItem` (RV.38): one fill-up with a BLANK price plus a pending item
///   whose reading fills that price and disagrees with the typed total - the
///   shape that lets the decline/accept suites assert hard rule 13. The RICH
///   case (five differing fields) is the RV.38 bell screenshot.
/// - `-seedInboxComparison` (RV.45): exactly ONE differing field (volume) and
///   ONE blank field (unit price), everything else agreeing. That is the
///   "interesting case" the comparison card must render, and the shape that
///   lets the L4 suite assert exactly two ticks and the per-field merge.
/// - `-seedInboxComparisonPriced` (RV.274): the comparison shape with the saved
///   entry ALSO carrying a price that differs from the receipt's, so BOTH price
///   columns render - the shape that proves the per-litre price converts in the
///   user column and the receipt column alike. `-seedInboxMiles` makes it
///   imperial.
/// - `-seedInboxNothingToChange` (RV.45 honesty rule 2): an item whose reading
///   AGREES with the saved entry - the no-op card must say so and offer no
///   update action.
/// - `-seedInboxServiceLines` (PJ.303): the same saved service with two lines
///   and a late reading whose lines pair onto them by title, not position - one
///   agrees (no offer), one differs (offered on the user's row), one is new -
///   and whose total does not add up to its lines (the amber flag).
/// - `-seedInboxService` (RV.201): a saved service invoice plus a late service
///   recognition that differs on vendor, line item and total - the shape that
///   proves the per-field ask reaches an entry kind that is not a fill-up.
/// - `-seedInboxExpense` (RV.215): a saved expense plus a late expense
///   recognition that differs on amount, category and date - the shape that
///   proves the ask reaches an expense, and the pose the expense screenshots use.
/// - `-seedInboxExpenseCurrency` (RV.280): the same expense with a FOREIGN late
///   read (PLN against the car's EUR) - the shape that proves the currency is
///   offered and the receipt's figure renders under its own symbol.
enum InboxTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedInboxItem") {
            seedRichItem()
        }
        if arguments.contains("-seedInboxComparison") {
            seedComparisonItem()
        }
        if arguments.contains("-seedInboxComparisonPriced") {
            seedPricedComparisonItem()
        }
        if arguments.contains("-seedInboxNothingToChange") {
            seedNothingToChangeItem()
        }
        if arguments.contains("-seedInboxService") {
            seedServiceItem()
        }
        if arguments.contains("-seedInboxServiceLines") {
            seedServiceItem(lines: true)
        }
        if arguments.contains("-seedInboxExpense") {
            seedExpenseItem()
        }
        if arguments.contains("-seedInboxExpenseCurrency") {
            seedExpenseItem(recognitionCurrency: .pln)
        }
    }

    private static func eur(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    /// The seeded car's units. Metric by default; `-seedInboxMiles` makes it an
    /// imperial car (miles, US gallons, MPG) so the comparison's volume values
    /// can be exercised in gallons (RV.271) - the same modifier shape
    /// `ManualFillUpTestSeed` and `HomeTestSeed` use.
    private static func unitsFromArguments() -> Vehicle.Units {
        ProcessInfo.processInfo.arguments.contains("-seedInboxMiles")
            ? Vehicle.Units(distance: .mi, volume: .galUS,
                            consumption: .mpgUS, energy: .miPerKWh)
            : Vehicle.Units(distance: .km, volume: .l,
                            consumption: .lPer100, energy: .kWhPer100)
    }

    // MARK: - RV.38 the rich item (blank price + five differing fields)

    @MainActor
    private static func seedRichItem() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedInboxItem") else { return }
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
        try? repository.upsertFillUp(fill)

        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.92),
            volume: .init(value: 55.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.500")!, confidence: 0.88),
            date: .init(value: "17.08.2026", confidence: 0.80),
            fuelKind: .init(value: .diesel, confidence: 0.70),
            currency: .init(value: .rub, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }

    // MARK: - RV.45 the comparison case (one differing + one blank field)

    @MainActor
    private static func seedComparisonItem() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        // The saved entry: total + litres typed, the price left BLANK - exactly
        // one blank (unit price) and one value the receipt reads differently
        // (volume 40.00 vs 30.00). Everything else the receipt reads agrees, so
        // the card offers exactly two ticks.
        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "100.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 40.00, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
        try? repository.upsertFillUp(fill)

        // volume 30.00 DIFFERS (replaces 40.00); unitPrice 1.800 FILLS the blank.
        // total / fuel kind / currency agree; date is unread (nil), so it is not
        // listed - the card must not treat an unread field as a decision.
        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "100.00")!, confidence: 0.92),
            volume: .init(value: 30.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.800")!, confidence: 0.88),
            fuelKind: .init(value: .petrol95, confidence: 0.70),
            currency: .init(value: .eur, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }

    // MARK: - RV.274 the priced comparison (both price columns render)

    /// The comparison shape with the saved entry ALSO carrying a price, so both
    /// the user's and the receipt's price columns render. The saved 1.500 €/L
    /// differs from the receipt's 1.800 €/L, so the price is offered and both
    /// per-litre figures cross the same display-unit boundary.
    @MainActor
    private static func seedPricedComparisonItem() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "100.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 40.00, unitPrice: Decimal(string: "1.500")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
        try? repository.upsertFillUp(fill)

        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "100.00")!, confidence: 0.92),
            volume: .init(value: 40.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.800")!, confidence: 0.88),
            fuelKind: .init(value: .petrol95, confidence: 0.70),
            currency: .init(value: .eur, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }

    // MARK: - RV.45 the nothing-to-change case (the reading agrees)

    @MainActor
    private static func seedNothingToChangeItem() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let entryID = UUID.v7()
        let fill = FillUp(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(fill)

        // The reading AGREES with every field the entry holds; the date is
        // unread. An agreeing answer would never be offered an item in the real
        // path, but the entry may have changed after the item was created - the
        // card must then say "nothing to change" and offer no update.
        let extraction = GatewayExtraction(
            total: .init(value: Decimal(string: "71.02")!, confidence: 0.92),
            volume: .init(value: 42.30, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.88),
            fuelKind: .init(value: .petrol95, confidence: 0.70),
            currency: .init(value: .eur, confidence: 0.60),
            pipeline: "seed")
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, extraction: extraction)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }

    // MARK: - RV.201 the service offer (a differing vendor, line and total)

    /// A saved service invoice plus a late service recognition that DIFFERS on
    /// vendor, line item and total. The card must offer those three per field
    /// (`inboxTick_vendor`, `inboxTick_lineItem_0`, `inboxTick_total`) and the
    /// user must be able to decline it. This is the seed the RV.201 L4 suite and
    /// the EN/RU screenshots use.
    @MainActor
    private static func seedServiceItem(lines: Bool = false) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let entryID = UUID.v7()
        let service = ServiceRecord(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "200.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Old Garage",
            items: [ServiceItem(title: "Oil change", category: .oil, cost: eur("80.00"))]
                + (lines ? [ServiceItem(title: "Brake pads front", category: .brakes, cost: eur("89.00"))] : []),
            usedParts: [], tireSetId: nil)
        try? repository.upsertServiceRecord(service)

        // The reordered cloud lines: the brake line first, the oil line second,
        // so a by-position pairing would offer the oil line against the brake
        // row - the trap PJ.302's matcher exists to avoid.
        let lineItems: [ServiceRecognition.LineItem] = lines
            ? [.init(title: "BRAKE PADS FRONT", category: .brakes, cost: eur("95.00")),
               .init(title: "Oil change", category: .oil, cost: eur("80.00")),
               .init(title: "Environmental fee", category: .other(""), cost: eur("3.50"))]
            : [.init(title: "Brake pads", category: .brakes, cost: eur("120.00"))]
        let recognition = InboxRecognition.service(ServiceRecognition(
            vendor: .init(value: "New Garage", confidence: 0.9),
            total: .init(value: Decimal(string: "250.00")!, confidence: 0.9),
            currency: .init(value: .eur, confidence: 0.9),
            lineItems: lineItems,
            doesNotAddUp: lines))
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, recognition: recognition)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }

    // MARK: - RV.215 the expense offer (a differing amount, category and date)

    /// A saved expense plus a late expense recognition that DIFFERS on amount,
    /// category and date (and, when `recognitionCurrency` is given, on currency
    /// too - RV.280). The card must offer `inboxTick_total`,
    /// `inboxTick_category` and `inboxTick_date` (plus `inboxTick_currency` for
    /// the foreign pose) and the user must be able to decline it. This is the
    /// seed the expense EN/RU screenshots use; the L4 test drives the REAL
    /// deferred producer instead.
    @MainActor
    private static func seedExpenseItem(recognitionCurrency: CurrencyCode? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Test Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Self.unitsFromArguments(),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let entryID = UUID.v7()
        let expense = Expense(
            id: entryID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .accessory, title: "Shop")
        try? repository.upsertExpense(expense)

        let recognition = InboxRecognition.expense(ExpenseRecognition(
            total: .init(value: Decimal(string: "20.00")!, confidence: 0.9),
            currency: recognitionCurrency.map { .init(value: $0, confidence: 0.9) },
            category: .init(value: .parking, confidence: 0.8),
            date: .init(value: now.addingTimeInterval(-7 * 86_400), confidence: 0.9)))
        let item = GatewayInboxItem(id: UUID.v7(), entryId: entryID,
                                    createdAt: now, recognition: recognition)
        if let data = try? JSONEncoder().encode([item]) {
            UserDefaults.standard.set(data, forKey: AppInbox.storageKey)
        }
    }
}

#endif
