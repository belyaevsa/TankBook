import Testing
import Foundation
@testable import TankbookCore

/// RV.112 - the vitals tile and the Trends series must never report a
/// rate-pending month as zero (the defect RV.106 fixed on the divider but left
/// on HomeStats and the Trends monthly series).
///
/// The claims, each against ALL THREE surfaces so the shared accumulator is
/// asserted through the seam and not assumed: an all-pending month is
/// `.pending` from `HomeStats` and yields no point from either Trends series; a
/// MIXED month is `.partial` with the exact known sum and the correct
/// `pendingCount`; a fully-converted month is `.complete` to the cent; and a
/// fixture holding a purchase group and an unresolved S2 duplicate pair
/// classifies identically on LogStream, HomeStats and TrendsStats - the
/// single-count invariants (hard rule 4, docs/SYNC.md S2) carried through the
/// one accumulator.
struct MonthTotalPendingSurfacesTests {

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

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.date(2025, 6, 1), updatedAt: Self.date(2025, 6, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func homeMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    /// A rate-pending pair: the amount is known in its original currency (PLN)
    /// but the home (EUR) value is not resolved yet - the RV.112 shape.
    private static func pendingMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .pln, homeCurrency: .eur)
    }

    private static func fill(_ d: Date, odo: Int, amount: String, volume: Double = 42,
                             vehicleID: UUID = UUID.v7(), group: UUID? = nil,
                             money: Money? = nil,
                             createdAt: Date? = nil) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: createdAt ?? d, updatedAt: d, deletedAt: nil,
            vehicleId: vehicleID, date: d, odometer: odo,
            money: money ?? Self.homeMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            volumeL: volume, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private static func expense(_ d: Date, amount: String, group: UUID? = nil,
                                money: Money? = nil) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: d, updatedAt: d, deletedAt: nil,
            vehicleId: UUID.v7(), date: d, odometer: nil,
            money: money ?? Self.homeMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: "Parking", recurrence: nil,
            installedInServiceId: nil)
    }

    /// The slot for one month in a Trends monthly series.
    private static func slot(_ monthStart: Date, in series: [TrendsMonthSlot]) -> TrendsMonthSlot? {
        series.first { $0.date == monthStart }
    }

    // MARK: - An all-pending month is pending, never a zero, on every surface

    @Test func allPendingMonthIsPendingOnHomeAndYieldsNoPointOnEitherTrendsSeries() {
        let month = Self.date(2026, 8, 10)
        let vehicleID = UUID.v7()
        let entries: [any Entry] = [
            Self.fill(month, odo: 120_000, amount: "289.50", vehicleID: vehicleID,
                      money: Self.pendingMoney("289.50")),
            Self.fill(Self.date(2026, 8, 15), odo: 120_800, amount: "294.00",
                      vehicleID: vehicleID, money: Self.pendingMoney("294.00"))
        ]

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == LogStream.MonthTotal.pending(pendingCount: 2),
                "an all-pending month must be .pending from HomeStats, never a zero figure")

        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        let monthStart = Self.calendar().dateInterval(of: .month, for: month)!.start
        #expect(Self.slot(monthStart, in: trends.spendSeries) == .gap(monthStart),
                "a pending month must not plot a spend point")
        #expect(Self.slot(monthStart, in: trends.costSeries) == .gap(monthStart),
                "a pending month with a km span must not plot a cost/km point")
        #expect(!trends.spendSeries.contains { $0 == .point(TrendPoint(date: monthStart, value: 0)) },
                "a pending month must never sit at a zero point")
    }

    // MARK: - A mixed month is partial, its figure the exact known sum

    @Test func mixedMonthIsPartialFromHomeWithTheExactKnownSumAndNoTrendsPoint() {
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, odo: 118_000, amount: "68.46"),                            // converted
            Self.fill(Self.date(2026, 8, 12), odo: 118_600, amount: "289.50",
                      money: Self.pendingMoney("289.50")),                              // pending
            Self.expense(Self.date(2026, 8, 15), amount: "148.00"),                     // converted
            Self.fill(Self.date(2026, 8, 18), odo: 119_200, amount: "294.00",
                      money: Self.pendingMoney("294.00"))                               // pending
        ]
        let known = Decimal(string: "68.46")! + Decimal(string: "148.00")!

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == LogStream.MonthTotal.partial(amount: known,
                                                                currency: .eur,
                                                                pendingCount: 2))

        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        let monthStart = Self.calendar().dateInterval(of: .month, for: month)!.start
        #expect(Self.slot(monthStart, in: trends.spendSeries) == .gap(monthStart),
                "a partial month must not plot a spend point at its known-so-far sum")
        #expect(Self.slot(monthStart, in: trends.costSeries) == .gap(monthStart),
                "a partial month must not plot a cost/km point at its understated total")
    }

    // MARK: - A fully-converted month is complete, to the cent, on all three surfaces

    @Test func fullyConvertedMonthIsCompleteToTheCentOnAllThreeSurfaces() {
        let month = Self.date(2026, 8, 5)
        let entries: [any Entry] = [
            Self.fill(month, odo: 118_000, amount: "107.25"),
            Self.fill(Self.date(2026, 8, 18), odo: 118_600, amount: "101.71")
        ]
        let exact = Decimal(string: "107.25")! + Decimal(string: "101.71")!

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.monthSpend == LogStream.MonthTotal.complete(amount: exact, currency: .eur))

        let stream = LogStream(vehicle: Self.vehicle(), entries: entries,
                               calendar: Self.calendar())
        #expect(stream.sections[0].total == LogStream.MonthTotal.complete(amount: exact, currency: .eur),
                "the divider and HomeStats must agree to the cent")
        #expect(home.monthSpend == stream.sections[0].total)

        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        let monthStart = Self.calendar().dateInterval(of: .month, for: month)!.start
        let point = (exact as NSDecimalNumber).doubleValue
        #expect(Self.slot(monthStart, in: trends.spendSeries)
                == .point(TrendPoint(date: monthStart, value: point)),
                "a complete month must plot its exact figure - the regression guard")
    }

    // MARK: - The shared accumulator's single-count invariants through the seam

    /// One fixture, one calendar month, three surfaces: a purchase group (a
    /// converted fill + a converted expense from one receipt), an unresolved S2
    /// duplicate pair (a converted counted member + a rate-pending excluded
    /// member), a standalone converted fill and a standalone rate-pending
    /// expense. The excluded member's pending state must never leak (it does
    /// not count anywhere, docs/SYNC.md S2) and the group must contribute its
    /// grand total once (hard rule 4) - asserted as the EXACT partial figure and
    /// pending count every surface agrees on, so a regression that double-counts
    /// the pair or leaks the excluded row fails the equality.
    @Test func allSurfacesClassifyTheSameGroupAndDuplicateFixtureIdentically() {
        let month = Self.date(2026, 8, 5)
        let vehicleID = UUID.v7()
        let groupID = UUID.v7()
        let countedDay = Self.date(2026, 8, 12, 9)
        let entries: [any Entry] = [
            // The purchase group: fuel + car wash from one receipt.
            Self.fill(Self.date(2026, 8, 3), odo: 118_000, amount: "71.02",
                      volume: 42.3, vehicleID: vehicleID, group: groupID),
            Self.expense(Self.date(2026, 8, 3, 10), amount: "8.00", group: groupID),
            // The S2 pair: counted converted, excluded rate-pending (created
            // later). Only the counted member ever counts (docs/SYNC.md S2).
            Self.fill(countedDay, odo: 120_000, amount: "68.46", volume: 42,
                      vehicleID: vehicleID),
            Self.fill(countedDay.addingTimeInterval(900), odo: 120_000, amount: "289.50",
                      volume: 42, vehicleID: vehicleID,
                      money: Self.pendingMoney("289.50"),
                      createdAt: countedDay.addingTimeInterval(900)),
            // A standalone converted fill and a standalone pending expense.
            Self.fill(Self.date(2026, 8, 18), odo: 121_000, amount: "60.00",
                      volume: 50, vehicleID: vehicleID),
            Self.expense(Self.date(2026, 8, 19), amount: "8.00",
                         money: Self.pendingMoney("8.00"))
        ]
        // Known = the group's grand total (71.02 + 8.00), the pair's COUNTED
        // member (68.46 - never the excluded 289.50), and the standalone fill
        // (60.00). One pending row remains: the standalone pending expense.
        let known = Decimal(string: "71.02")! + Decimal(string: "8.00")!
            + Decimal(string: "68.46")! + Decimal(string: "60.00")!
        let expected = LogStream.MonthTotal.partial(amount: known, currency: .eur, pendingCount: 1)

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries,
                               calendar: Self.calendar())
        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())

        #expect(home.monthSpend == expected,
                "HomeStats must count the group once and the pair's counted member only")
        #expect(stream.sections[0].total == expected,
                "the Log divider must agree to the exact partial figure and count")
        #expect(home.monthSpend == stream.sections[0].total,
                "HomeStats and the Log divider cannot disagree about the month")
        #expect(stream.allRows.contains { row in
            if case .duplicate = row { return true }
            return false
        }, "the fixture must actually hold an unresolved duplicate pair")

        let monthStart = Self.calendar().dateInterval(of: .month, for: month)!.start
        #expect(Self.slot(monthStart, in: trends.spendSeries) == .gap(monthStart),
                "a partial month through the shared seam must be a gap on Trends, never a point")
        #expect(home.pendingRateCount == 1,
                "the excluded member must not count as pending anywhere")
    }
}
