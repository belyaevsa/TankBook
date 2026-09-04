#if DEBUG
import Foundation
import TankbookCore

// MARK: - RV.62 screenshots + UI-test seeding

/// Seeds one vehicle so the ExpenseEntry sheet can render without a prior
/// entry, plus the canned recognitions and pre-fills the RV.62 screenshots and
/// UI tests drive. Same test-hook pattern as `ServiceEntryTestSeed` /
/// `ManualFillUpTestSeed`: idempotent (once a vehicle exists it does nothing),
/// and each seed is consumed by the exact load path a real scan uses so the
/// test cannot drift from shipped behaviour.
enum ExpenseEntryTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedVehicleForUITests") {
            ManualFillUpTestSeed.seedIfRequested()
            return
        }
        guard arguments.contains("-seedExpenseEntryPrefill")
            || arguments.contains("-seedExpenseScan")
            || arguments.contains("-seedExpenseScanEmpty") else { return }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

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
        try? repository.upsertVehicle(vehicle)
    }
}

/// The ExpenseEntry form's pre-fill, shared by the screenshot seed and the
/// scanned path (RV.62). Whatever it carries is default input the user edits
/// (hard rule 13), never a separate screen. Only total / currency / date exist
/// - the type (`ExpensePrefill`, core) is the boundary that keeps liters and
/// fuel kind out of an expense form.
enum ExpenseEntryPrefillSeed {
    /// - `-seedExpenseEntryPrefill` - the RV.62 pre-filled state: a shop
    ///   receipt resolved total 12.40 EUR and date 09.08.2026, category and
    ///   title left to the user (a scan never guesses a category).
    static func from(arguments: [String]) -> ExpensePrefill? {
        guard arguments.contains("-seedExpenseEntryPrefill") else { return nil }
        return ExpensePrefill(
            total: Decimal(string: "12.40"),
            currency: .eur,
            date: ConfirmDate.parse("09.08.2026"))
    }
}

/// The canned recognitions for the Expense-mode capture path (RV.62). The real
/// path runs `CapturePipeline` (Vision OCR); these arguments substitute a fixed
/// `FuelExtraction` so a UI test can assert what the user SEES without
/// depending on OCR over a corpus image - the same seam `ConfirmPrefillSeed`
/// gives the fill-up Confirm sheet:
/// - `-seedExpenseScan` - the resolved state (total 71.02 EUR, 17.08.2026),
///   deliberately ALSO carrying liters / unitPrice / fuelKind, so the L4 test
///   proves the fuel fields never reach the expense form.
/// - `-seedExpenseScanForeign` - a total priced in a currency the home-only
///   expense form cannot express (289.50 PLN, home EUR): the amount must NOT
///   be offered as if it were EUR.
/// - `-seedExpenseScanEmpty` - an all-nil extraction: the expense form opens
///   empty with no error (hard rule 7).
enum ExpenseScanTestSeed {
    static func extraction(from arguments: [String]) -> FuelExtraction? {
        if arguments.contains("-seedExpenseScan") {
            return FuelExtraction(liters: 42.30, unitPrice: 1.679, total: 71.02,
                                  currency: .eur, fuelKind: .petrol95,
                                  date: "17.08.2026")
        }
        if arguments.contains("-seedExpenseScanForeign") {
            return FuelExtraction(total: 289.50, currency: .pln, date: "17.08.2026")
        }
        if arguments.contains("-seedExpenseScanEmpty") {
            return FuelExtraction()
        }
        return nil
    }
}
#endif
