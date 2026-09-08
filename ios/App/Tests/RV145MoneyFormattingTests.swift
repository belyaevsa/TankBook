import XCTest
import TankbookCore
@testable import Tankbook

/// RV.145 L1 - the app-layer money formatters. The five month-spend surfaces
/// (the Log divider, the vitals tile, the guest strip, `VehicleVitals` and the
/// Trends spend tile) all render through `HomeFormat.spend(LogStream.MonthTotal)`,
/// so the pairing tests here hold for every one of them: a figure is always
/// printed with the marker of the currency it is DENOMINATED in - never the
/// vehicle's - and a currency whose symbol is not distinct from its code (CHF)
/// falls back to the code, through the one named resolver (`moneySymbol`).
final class RV145MoneyFormattingTests: XCTestCase {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    private func code(_ raw: String) -> CurrencyCode { CurrencyCode(rawValue: raw)! }

    // MARK: - Symbols everywhere, code only as the fallback

    /// Every money figure renders a symbol; the ISO code appears ONLY for a
    /// currency whose symbol resolves empty. CHF is the live case: its chips
    /// are offered, `currencySymbol` returns "" for it, and a CHF figure used
    /// to render `2416.00 ` with no marker at all.
    func testMoneySymbolRendersTheSymbolAndFallsBackToTheCodeForCHF() {
        XCTAssertEqual(AddVehicleSupport.moneySymbol(for: .eur), "€")
        XCTAssertEqual(AddVehicleSupport.moneySymbol(for: .usd), "$")
        XCTAssertEqual(AddVehicleSupport.moneySymbol(for: .pln), "zł")
        let chf = code("CHF")
        XCTAssertEqual(AddVehicleSupport.currencySymbol(for: chf), "",
                       "CHF has no symbol distinct from its code - the chip path stays empty")
        XCTAssertEqual(AddVehicleSupport.moneySymbol(for: chf), "CHF",
                       "a money figure falls back to the ISO code, never to nothing")
    }

    /// A converted row's figure and the CHF fallback, formatted as the log row
    /// and the Recently-deleted list format an entry amount.
    func testEntryAmountCarriesASymbolNeverABareFigure() {
        XCTAssertEqual(HomeFormat.entryAmount(decimal("2416.00"),
                                              symbol: AddVehicleSupport.moneySymbol(for: .usd)),
                       "2416.00\u{00A0}$")
        XCTAssertEqual(HomeFormat.entryAmount(decimal("2416.00"),
                                              symbol: AddVehicleSupport.moneySymbol(for: code("CHF"))),
                       "2416.00\u{00A0}CHF",
                       "a CHF home figure must render a marker, not a bare number")
    }

    // MARK: - A figure and its marker come from the same object

    /// `HomeFormat.spend(MonthTotal)` renders each total with the currency the
    /// total CAME WITH - the divider, the vitals tile, the guest strip and the
    /// Trends spend tile all route through it, so a `.complete` in EUR can
    /// never be printed under a `$` from the car.
    func testMonthTotalSpendUsesTheCarriedCurrencyNotTheVehicle() {
        let eurMonth = LogStream.MonthTotal.complete(amount: decimal("91.43"), currency: .eur)
        XCTAssertEqual(HomeFormat.spend(eurMonth), "91\u{00A0}€",
                       "a EUR month renders the euro, whatever the car's home currency is")

        let usdMonth = LogStream.MonthTotal.complete(amount: decimal("91.43"), currency: .usd)
        XCTAssertEqual(HomeFormat.spend(usdMonth), "91\u{00A0}$")
    }

    /// A `.partial` month (pending rows beside a known single-currency sum)
    /// formats its known figure with the carried currency, unchanged.
    func testPartialMonthFormatsItsKnownFigureInItsOwnCurrency() {
        let partial = LogStream.MonthTotal.partial(amount: decimal("68.46"), currency: .eur,
                                                   pendingCount: 2)
        XCTAssertEqual(HomeFormat.spend(partial), "68\u{00A0}€")
    }

    /// A `.mixed` month renders its per-currency breakdown - each subtotal with
    /// its own marker - never a bare sum across currencies (hard rule 3).
    func testMixedMonthRendersPerCurrencySubtotalsNotASum() {
        let mixed = LogStream.MonthTotal.mixed(
            subtotals: [.init(amount: decimal("68.46"), currency: .eur),
                        .init(amount: decimal("30.00"), currency: .usd)],
            pendingCount: 0)
        XCTAssertEqual(HomeFormat.spend(mixed), "68\u{00A0}€ · 30\u{00A0}$",
                       "the breakdown lists each currency's exact share with its own symbol")
        XCTAssertFalse(HomeFormat.spend(mixed)!.contains("98"),
                       "a mixed month must never render the cross-currency sum")
    }

    /// A `.pending` month has no figure: the formatter returns nil and the
    /// surfaces print the pending phrase instead.
    func testPendingMonthHasNoFigure() {
        XCTAssertNil(HomeFormat.spend(.pending(pendingCount: 2)))
    }

    // MARK: - End to end through the model a renderer actually sees

    /// A USD car whose rows are EUR-homed (the owner's 2026-09-08 scene):
    /// `VehicleVitals` must state the month in euros. Before RV.145 this
    /// surface stamped the vehicle's `$` on the euro sum.
    func testVehicleVitalsOnAUSDHomeCarStatesAnEURMonthInEuros() throws {
        let vehicle = Vehicle(id: UUID.v7(), createdAt: Date(), updatedAt: Date(),
                              deletedAt: nil, name: "Volvo V60", make: "Volvo",
                              model: "V60", year: 2015, plate: nil, powertrain: .ice,
                              fuelKinds: [.petrol95], tankCapacityL: 71,
                              batteryCapacityKWh: nil, homeCurrency: .usd,
                              units: Vehicle.Units(distance: .km, volume: .l,
                                                   consumption: .lPer100, energy: .kWhPer100),
                              photo: nil, archived: false, paceLimitKmPerDay: 1500,
                              initialOdometer: 118_000)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = { (day: Int, hour: Int) in
            calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
        }
        let makeEntry = { (date: Date, odo: Int, volume: Double, amount: String) in
            FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                   vehicleId: vehicle.id, date: date, odometer: odo,
                   money: Money(amount: self.decimal(amount), currency: .eur, homeCurrency: .eur),
                   note: nil, attachments: [], provenance: .manual, conflict: .none,
                   purchaseGroupId: nil, volumeL: volume, unitPrice: nil, fuelKind: .petrol95,
                   fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
                   crossCheck: .verified, extraction: nil)
        }
        // Distinct days and strictly rising odometers so the S2 duplicate
        // heuristic (same vehicle, within 30 minutes, volume within 5%) cannot
        // pair any two rows.
        let entries: [any Entry] = [
            makeEntry(day(8, 9), 118_600, 40.0, "36.06"),
            makeEntry(day(12, 9), 119_400, 42.0, "28.78"),
            makeEntry(day(16, 9), 120_200, 44.0, "26.59")
        ]
        let asOf = day(20, 12)

        let stats = HomeStats(vehicle: vehicle, entries: entries, asOf: asOf, calendar: calendar)
        guard let monthSpend = stats.monthSpend else {
            return XCTFail("the fixture month must have a total")
        }
        XCTAssertEqual(monthSpend,
                       LogStream.MonthTotal.complete(amount: self.decimal("91.43"),
                                                     currency: .eur))
        let line = VehicleVitals.line(stats)
        XCTAssertTrue(line.contains("91\u{00A0}€"), "the vitals line states the EUR month in euros: \(line)")
        XCTAssertFalse(line.contains("$"), "no figure on the line may carry the car's dollar: \(line)")
    }
}
