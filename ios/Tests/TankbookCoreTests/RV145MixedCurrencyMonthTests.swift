import Testing
import Foundation
@testable import TankbookCore

/// RV.145 - a month's total is printable only when its addends share one home
/// currency, and every amount carries the currency it is denominated in.
///
/// The owner's defect had two live mechanisms (2026-09-08): the divider took
/// its symbol from the VEHICLE while each row took its own money pair's home
/// currency (a euro sum printed `91 $`), and the accumulator summed every known
/// `homeAmount` without reading `homeCurrency`, so a garage holding entries
/// homed in two currencies yielded a number that was not a quantity of
/// anything (hard rule 2 - a derived figure asserting a falsehood). RV.106 and
/// RV.112 fixed the pending/known axis; this row fixes the currency axis.
///
/// The claims: a month whose KNOWN figures are homed in two currencies is
/// `.mixed` (never a bare number) from every deriving surface; a single-
/// currency month on a vehicle whose home differs still carries ITS OWN
/// currency - the figure that fails today - to the cent; a rate-pending row
/// contributes nothing and is only counted; and the Trends monthly series
/// leaves a mixed month as a hole, never a point at a cross-currency sum.
struct RV145MixedCurrencyMonthTests {

    // A fixed UTC Gregorian calendar so month boundaries are deterministic, and
    // a fixed "now" (2026-08-20) whose trailing-12-month window contains the
    // fixture months below.
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let asOf = date(2026, 8, 20)

    private static func vehicle(home: CurrencyCode = .eur) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.date(2025, 6, 1), updatedAt: Self.date(2025, 6, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: home,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    /// A converted pair whose snapshot is denominated in `home` - the stamped
    /// home currency a written row keeps even after the car's setting moves
    /// (docs/SCHEMA.md -> Money: re-homing touches only rate-pending rows).
    private static func convertedMoney(amount: String, currency: CurrencyCode,
                                       home: CurrencyCode) -> Money {
        Money(amount: Decimal(string: amount)!, currency: currency, homeCurrency: home)
    }

    /// A rate-pending pair asking for a rate into `home`.
    private static func pendingMoney(amount: String, home: CurrencyCode) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .pln, homeCurrency: home)
    }

    private static func fill(_ date: Date, odo: Int, amount: String,
                             currency: CurrencyCode = .eur, home: CurrencyCode = .eur,
                             money: Money? = nil) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odo,
            money: money ?? Self.convertedMoney(amount: amount, currency: currency, home: home),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42, unitPrice: nil, fuelKind: .petrol95,
            fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private static func expense(_ date: Date, amount: String,
                                currency: CurrencyCode = .eur, home: CurrencyCode = .eur,
                                money: Money? = nil) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: money ?? Self.convertedMoney(amount: amount, currency: currency, home: home),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .parking, title: "Parking",
            installedInServiceId: nil)
    }

    /// The slot for one month in a Trends monthly series.
    private static func slot(_ monthStart: Date, in series: [TrendsMonthSlot]) -> TrendsMonthSlot? {
        series.first { $0.date == monthStart }
    }

    /// A `SpendSubtotal` helper so expectations read as amounts, not plumbing.
    private static func subtotal(_ amount: String, _ currency: CurrencyCode) -> LogStream.SpendSubtotal {
        LogStream.SpendSubtotal(amount: Decimal(string: amount)!, currency: currency)
    }

    // MARK: - A mixed-currency month is `.mixed`, never a bare number

    /// A month whose KNOWN figures are homed in two currencies (EUR rows left
    /// over from an old car home, USD rows recorded since) cannot state one
    /// number: the classifier must return `.mixed` from HomeStats and the Log
    /// divider, and both Trends series must leave the month a hole - a point at
    /// 68.46 + 30 = 98.46 would be a sum of euros and dollars (hard rule 2).
    /// A rate-pending row is only counted, never summed.
    @Test func monthWithKnownFiguresInTwoHomeCurrenciesIsMixedOnEverySurface() {
        let month = Self.date(2026, 8, 10)
        let vehicleID = UUID.v7()
        let entries: [any Entry] = [
            Self.fill(month, odo: 118_000, amount: "68.46",
                      currency: .eur, home: .eur, money: nil),
            Self.expense(Self.date(2026, 8, 14), amount: "30.00",
                         currency: .usd, home: .usd),
            Self.fill(Self.date(2026, 8, 16), odo: 118_600, amount: "289.50",
                      money: Self.pendingMoney(amount: "289.50", home: .eur))
        ]
        // Dominant currency leads the breakdown (68.46 EUR > 30 USD), exactly
        // the order the shared classifier emits.
        let expected = LogStream.MonthTotal.mixed(
            subtotals: [Self.subtotal("68.46", .eur), Self.subtotal("30.00", .usd)],
            pendingCount: 1)

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == expected,
                "HomeStats must classify a two-currency month as .mixed, never a bare sum")

        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar())
        #expect(stream.sections[0].total == expected,
                "the Log divider must agree with HomeStats to the exact breakdown")

        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        let monthStart = Self.calendar().dateInterval(of: .month, for: month)!.start
        #expect(Self.slot(monthStart, in: trends.spendSeries) == .gap(monthStart),
                "a mixed month must not plot a spend point at a cross-currency sum")
        #expect(Self.slot(monthStart, in: trends.costSeries) == .gap(monthStart),
                "a mixed month must not plot a cost/km point at a cross-currency sum")
    }

    // MARK: - A month is printable only in ITS OWN currency (the failing case)

    /// A month whose known rows are ALL homed in EUR on a car whose home is now
    /// USD - the owner's exact shape. The rows' EUR figures must classify as a
    /// EUR `.complete`, never a bare sum the renderer could stamp with the
    /// car's `$`; every deriving surface reports the currency with the amount.
    @Test func singleCurrencyMonthOnAForeignHomeCarStillCarriesItsOwnCurrency() {
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, odo: 118_000, amount: "36.06", currency: .eur, home: .eur),
            Self.fill(Self.date(2026, 8, 12), odo: 118_500, amount: "28.78",
                      currency: .eur, home: .eur),
            Self.fill(Self.date(2026, 8, 15), odo: 119_000, amount: "26.59",
                      currency: .eur, home: .eur)
        ]
        let exact = Decimal(string: "36.06")! + Decimal(string: "28.78")!
            + Decimal(string: "26.59")!
        let expected = LogStream.MonthTotal.complete(amount: exact, currency: .eur)

        let home = HomeStats(vehicle: Self.vehicle(home: .usd), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == expected,
                "a EUR month on a USD car must be reported in EUR, never the vehicle's currency")

        let stream = LogStream(vehicle: Self.vehicle(home: .usd), entries: entries,
                               calendar: Self.calendar())
        #expect(stream.sections[0].total == expected,
                "the divider must carry the figure's own currency on a foreign-home car")
        #expect(home.monthSpend == stream.sections[0].total,
                "HomeStats and the divider cannot disagree about a month's currency")
        #expect(stream.sections[0].total != LogStream.MonthTotal.complete(amount: exact, currency: .usd),
                "the sum of euro figures must never be stated as dollars - the owner's `91 $`")
    }

    // MARK: - Pending rows never force or poison a currency

    /// Rate-pending rows are counted but contribute no figure, so a month whose
    /// only KNOWN figures are one currency stays `.partial` in that currency
    /// even when the pending rows ask for a different home - a pending row is a
    /// missing amount, not a second currency.
    @Test func pendingRowsDoNotCreateAMixedStateOnTheirOwn() {
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, odo: 118_000, amount: "68.46", currency: .eur, home: .eur),
            // A USD-home car's pending row asks for a rate into USD.
            Self.fill(Self.date(2026, 8, 14), odo: 118_600, amount: "289.50",
                      money: Self.pendingMoney(amount: "289.50", home: .usd))
        ]
        let known = Decimal(string: "68.46")!

        let home = HomeStats(vehicle: Self.vehicle(home: .usd), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == LogStream.MonthTotal.partial(amount: known,
                                                                currency: .eur,
                                                                pendingCount: 1),
                "a pending row never contributes a home figure, so it cannot mix currencies")
    }

    // MARK: - A single-currency month is unchanged, to the cent

    /// The regression guard for the untouched axis: a normal month - every row
    /// homed in the vehicle's own currency, nothing pending - must classify
    /// `.complete` with the exact figure and plot its point, exactly as before
    /// RV.145.
    @Test func fullyConvertedSingleCurrencyMonthIsUnchangedToTheCent() {
        let month = Self.date(2026, 8, 5)
        let entries: [any Entry] = [
            Self.fill(month, odo: 118_000, amount: "107.25"),
            Self.fill(Self.date(2026, 8, 18), odo: 118_600, amount: "101.71")
        ]
        let exact = Decimal(string: "107.25")! + Decimal(string: "101.71")!
        let expected = LogStream.MonthTotal.complete(amount: exact, currency: .eur)

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == expected)

        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar())
        #expect(stream.sections[0].total == expected,
                "the divider and HomeStats must agree to the cent")

        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        let monthStart = Self.calendar().dateInterval(of: .month, for: month)!.start
        let point = (exact as NSDecimalNumber).doubleValue
        #expect(Self.slot(monthStart, in: trends.spendSeries)
                == .point(TrendPoint(date: monthStart, value: point)),
                "a single-currency month must still plot its exact figure")
    }

    // MARK: - The zero figure is denominated in the vehicle's home

    /// A month of only free events has no money row to name a currency, so its
    /// honest `0` is stated in the vehicle's home currency - the divider's
    /// `0 €` behaviour before and after RV.145.
    @Test func moneyLessMonthReportsZeroInTheVehicleHomeCurrency() {
        let month = Self.date(2026, 8, 10)
        let free = Expense(
            id: UUID.v7(), createdAt: month, updatedAt: month, deletedAt: nil,
            vehicleId: UUID.v7(), date: month, odometer: nil,
            money: nil, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, category: .parking,
            title: "Free parking", installedInServiceId: nil)
        let stream = LogStream(vehicle: Self.vehicle(home: .usd), entries: [free],
                               calendar: Self.calendar())
        #expect(stream.sections[0].total == LogStream.MonthTotal.complete(amount: .zero,
                                                                          currency: .usd),
                "a zero-spend month is denominated in the car's home currency")
    }
}
