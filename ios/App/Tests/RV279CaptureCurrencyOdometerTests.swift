import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.279 - the Expense and Service capture forms carry the odometer and
/// currency fields Edit entry has, so the two doors to one entry are the same
/// screen. These L1 tests drive the persisted shape through the same seams the
/// real saves call (`ExpenseEntryView.writeExpense`, `storedExpense`,
/// `ServiceEntryFormState.draft`): a scanned foreign total pre-fills amount AND
/// currency; a foreign pick saves a pair whose currency is the pick and whose
/// home side is snapshotted at the entry's OWN date (or rate-pending when no
/// rate); a typed odometer lands on the record and a blank stays nil; and a
/// service record and its items agree on the chosen currency.
@MainActor
final class RV279CaptureCurrencyOdometerTests: XCTestCase {

    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func makeVehicle(homeCurrency: CurrencyCode = .eur) throws
        -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: homeCurrency,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    private func entryDay() -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 12))!
    }

    private func plnStore(on day: Date) -> RateStore {
        RateStore(seed: [
            ExchangeRate(base: .eur, quote: .pln, date: day,
                         rate: Decimal(string: "4.2706")!, source: .ecb)
        ], calendar: utcCalendar)
    }

    // MARK: - The scanned pre-fill

    /// A scanned foreign total is offered WITH its currency: the form carries a
    /// chip row now, so nothing is withheld (the RV.200 boundary relaxed).
    func testAScannedForeignTotalPrefillsTheAmountAndItsCurrency() {
        var form = ExpenseEntryFormState()
        form.apply(ExpensePrefill(total: Decimal(string: "289.50"),
                                  currency: .pln, date: nil))
        XCTAssertEqual(form.amountDecimal, Decimal(string: "289.50"),
                       "the recognised total must pre-fill the amount")
        XCTAssertEqual(form.currency, .pln,
                       "the total is offered with the currency the receipt priced it in")
    }

    // MARK: - The saved pair

    /// L1: a foreign pick saves a pair whose currency is the pick and whose home
    /// side is snapshotted at the entry's OWN date, never today.
    func testAForeignExpenseSavesASnapshotAtTheEntrysDate() throws {
        let (repository, vehicle) = try makeVehicle()
        let day = entryDay()
        var form = ExpenseEntryFormState()
        form.category = .parking
        form.amount = "289.50"
        form.currency = .pln
        form.date = day
        let amount = try XCTUnwrap(form.amountDecimal)

        let (expense, _) = try ExpenseEntryView.writeExpense(
            form: form, vehicle: vehicle, amount: amount, scan: nil,
            repository: repository, store: plnStore(on: day))

        XCTAssertEqual(expense.money?.currency, .pln,
                       "the saved pair's currency is the user's pick, never the home currency")
        XCTAssertEqual(expense.money?.homeCurrency, .eur)
        XCTAssertNotNil(expense.money?.homeAmount,
                        "a rate on the entry's day snapshots the pair")
        XCTAssertEqual(expense.money?.rateDate, utcCalendar.startOfDay(for: day),
                       "the snapshot is dated at the entry's own date, never today")
    }

    /// L1: with no rate for the entry's day the foreign pair saves rate-pending -
    /// conversion is metadata, never a save-blocker and never today's rate.
    func testAForeignExpenseWithNoRateSavesRatePending() throws {
        let (repository, vehicle) = try makeVehicle()
        let day = entryDay()
        var form = ExpenseEntryFormState()
        form.amount = "289.50"
        form.currency = .pln
        form.date = day
        let amount = try XCTUnwrap(form.amountDecimal)

        let (expense, _) = try ExpenseEntryView.writeExpense(
            form: form, vehicle: vehicle, amount: amount, scan: nil,
            repository: repository, store: RateStore(seed: [], calendar: utcCalendar))

        XCTAssertEqual(expense.money?.currency, .pln)
        XCTAssertNil(expense.money?.homeAmount,
                     "no rate for the day leaves the pair rate-pending")
    }

    /// The home-currency common case is unchanged: snapshotted at rate 1.
    func testAHomeCurrencyExpenseSavesSnapshottedAtRateOne() throws {
        let (repository, vehicle) = try makeVehicle()
        var form = ExpenseEntryFormState()
        form.amount = "12.40"
        form.currency = .eur
        let amount = try XCTUnwrap(form.amountDecimal)

        let (expense, _) = try ExpenseEntryView.writeExpense(
            form: form, vehicle: vehicle, amount: amount, scan: nil,
            repository: repository, store: RateStore(seed: [], calendar: utcCalendar))

        XCTAssertEqual(expense.money?.currency, .eur)
        XCTAssertEqual(expense.money?.homeAmount, Decimal(string: "12.40"))
    }

    // MARK: - The odometer

    /// L1: a typed odometer lands on the record; a blank stays nil - never the
    /// "last known" written as a fact (hard rule 13).
    func testATypedOdometerLandsOnTheRecordAndABlankStaysNil() throws {
        let (_, vehicle) = try makeVehicle()
        var typed = ExpenseEntryFormState()
        typed.amount = "12.40"
        typed.odometer = OdometerFormat.grouped(118_930)
        let withOdometer = ExpenseEntryView.storedExpense(
            form: typed, vehicle: vehicle, amount: Decimal(string: "12.40")!,
            attachments: [], provenance: .manual)
        XCTAssertEqual(withOdometer.odometer, 118_930,
                       "the typed odometer must land on the record")

        var blank = ExpenseEntryFormState()
        blank.amount = "12.40"
        blank.odometer = ""
        let withoutOdometer = ExpenseEntryView.storedExpense(
            form: blank, vehicle: vehicle, amount: Decimal(string: "12.40")!,
            attachments: [], provenance: .manual)
        XCTAssertNil(withoutOdometer.odometer,
                     "an expense away from the car has no odometer - blank stays nil")
    }

    // MARK: - The service record and its items agree

    /// L1: a service saved in a chosen foreign currency writes the record and
    /// every line item in that currency (PJ.58), so the two cannot disagree.
    func testAServiceInAChosenForeignCurrencySavesTheRecordAndItemsInThatCurrency() throws {
        let (_, vehicle) = try makeVehicle()
        var form = ServiceEntryFormState()
        form.vendor = "Bosch Service"
        form.currency = .pln
        form.items = [ServiceEntryItemDraft(title: "Oil service", category: .oil,
                                            cost: "89.00")]

        let record = form.draft(vehicle: vehicle)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency,
                   currency: form.currency)

        XCTAssertEqual(record.money?.currency, .pln,
                       "the record's money is in the chosen currency")
        XCTAssertEqual(record.items.first?.cost?.currency, .pln,
                       "the line item's cost agrees with the record")
    }
}
