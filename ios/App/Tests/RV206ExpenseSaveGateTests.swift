import TankbookCore
import XCTest
@testable import Tankbook

/// RV.206 - an expense with a category and an amount is saveable without a
/// title. The gate predates the fallback chain: when it was written a title was
/// the only thing naming an expense, so demanding one was right then. RV.187
/// gave the Log row a category fallback and RV.195 made the category visible
/// and editable, so the title became redundant typing - a complete scan landed
/// on a disabled Save with no way forward but the keyboard.
///
/// The amount requirement is kept: an untitled row is named by its category
/// (never a blank "- 12.40 €"), but an amount-less row is still refused. The
/// `.other("")` decision is asserted directly - it renders the localized
/// "Other", a real category label the user can edit afterwards (RV.195), so it
/// names the row like every other category.
///
/// The persisted shape is driven through `ExpenseEntryView.storedExpense`, the
/// same factory `save()` calls, so the round-trip proves what the real save
/// writes rather than a copy of it.
@MainActor
final class RV206ExpenseSaveGateTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    /// The premise of every test below: the form carries an amount and a
    /// category but no title. The gate must let it through.
    private func untitledForm(category: ExpenseCategory,
                              amount: String) -> ExpenseEntryFormState {
        var form = ExpenseEntryFormState()
        form.category = category
        form.amount = amount
        return form
    }

    private func logRowTitle(_ entry: Expense, vehicle: Vehicle) -> String? {
        let stream = LogStream(vehicle: vehicle, entries: [entry])
        let logEntry = stream.sections
            .flatMap(\.rows)
            .compactMap { row -> LogStream.LogEntry? in
                if case .entry(let value) = row { return value }
                return nil
            }
            .first
        return logEntry.map { EntryTitle.text($0, stations: []) }
    }

    // MARK: - The gate

    /// L1, fails before this row: a category and an amount with no title is
    /// saveable. Oracle: RV.187's chain - the Log row names it from the
    /// category, so the title is redundant input.
    func testAnExpenseWithACategoryAndAnAmountAndNoTitleIsSaveable() {
        let form = untitledForm(category: .parts, amount: "12.40")
        XCTAssertFalse(form.hasTitle, "the test's premise: no title was typed")
        XCTAssertTrue(form.canSave,
                      "a category names the row (RV.187), so a title is not required")
    }

    /// The gate still requires the amount. A title alone does not save, and
    /// neither does an empty form - deleting the gate outright is the vacuous
    /// trap this pins against.
    func testAnExpenseWithNoAmountIsStillRefused() {
        XCTAssertFalse(untitledForm(category: .parts, amount: "").canSave,
                       "an amount-less expense must not save as a blank row")
        var titled = untitledForm(category: .parts, amount: "")
        titled.title = "Oil filter"
        XCTAssertFalse(titled.canSave,
                       "a title does not stand in for the amount the row needs")
    }

    /// `.other("")` is a real category, not an absence: it renders the
    /// localized "Other" (RV.187, `expenseCategoryLabel`), so it names the row
    /// exactly as every fixed category does. Every offered category is
    /// asserted, so a later addition that cannot name a row fails here.
    func testEveryOfferedCategoryNamesTheRowWithoutATitle() {
        for category in ExpenseCategory.entryCases {
            let form = untitledForm(category: category, amount: "12.40")
            XCTAssertTrue(form.canSave,
                          "\(category) must name the row without a title")
            XCTAssertFalse(L10n.expenseCategoryLabel(category).isEmpty,
                           "\(category) must render a non-empty label")
        }
    }

    // MARK: - The save round-trips and the Log row reads the category

    /// L1: it actually SAVES and the stored row round-trips. Oracle: the
    /// reloaded `Expense` - empty title, the category, the amount - and the Log
    /// row it produces reads the category (RV.187), so the user can find what
    /// they saved. Never merely "the button is enabled".
    func testTheUntitledExpenseSavesAndItsLogRowReadsTheCategory() throws {
        let (repository, vehicle) = try makeVehicle()
        let form = untitledForm(category: .parts, amount: "12.40")
        let amount = try XCTUnwrap(form.amountDecimal)

        let expense = ExpenseEntryView.storedExpense(
            form: form, vehicle: vehicle, amount: amount,
            attachments: [], provenance: .manual)
        try repository.upsertExpense(expense)

        let saved = try XCTUnwrap(repository.liveExpenses(forVehicle: vehicle.id).first)
        XCTAssertEqual(saved.title, "", "the title is written as typed: blank")
        XCTAssertEqual(saved.category, .parts)
        XCTAssertEqual(saved.money?.amount, Decimal(string: "12.40"))
        XCTAssertEqual(logRowTitle(saved, vehicle: vehicle), "Parts",
                       "the Log row must name the untitled expense from its category")
    }

    /// L1, the `.other("")` decision asserted directly: an untitled expense in
    /// the bare other category saves and its Log row reads "Other" - a real
    /// label, not the bare type name and not a blank row.
    func testABareOtherCategoryNamesTheSavedRowAsOther() throws {
        let (repository, vehicle) = try makeVehicle()
        let form = untitledForm(category: .other(""), amount: "12.40")
        let amount = try XCTUnwrap(form.amountDecimal)

        let expense = ExpenseEntryView.storedExpense(
            form: form, vehicle: vehicle, amount: amount,
            attachments: [], provenance: .manual)
        try repository.upsertExpense(expense)

        let saved = try XCTUnwrap(repository.liveExpenses(forVehicle: vehicle.id).first)
        XCTAssertEqual(saved.title, "")
        XCTAssertEqual(saved.category, .other(""))
        XCTAssertEqual(logRowTitle(saved, vehicle: vehicle), "Other",
                       "the bare .other(\"\") still names the row 'Other'")
    }
}
