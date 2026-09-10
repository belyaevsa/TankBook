import Testing
import Foundation
@testable import TankbookCore

/// RV.166 - a purchase group's header figure is as honest as the month
/// divider's. Its own suite (and file) so `LogStreamTests` stays under the lint
/// body-length ceiling; same fixture shape as `LogStreamDividerRatePendingTests`.
///
/// The claims: a group with known members AND a rate-pending member is
/// `.partial` - its known sum marked with the pending count, never a bare total
/// that reads as the whole receipt while one line still waits (RV.106's lie, in
/// the group's own header this time); an all-known group is `.complete` to the
/// cent; a group whose KNOWN lines span home currencies is `.mixed` with no bare
/// figure (RV.145, unchanged); and the group classifies through the SAME
/// accumulator the month divider reduces through, so the two can never disagree.
struct LogStreamGroupTotalTests {

    // A fixed UTC Gregorian calendar so month boundaries are deterministic.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.date(2026, 6, 1), updatedAt: Self.date(2026, 6, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    /// Same-currency money (amount == home amount, snapshotted at rate 1).
    private static func homeMoney(_ amount: String, home: CurrencyCode) -> Money {
        Money(amount: Decimal(string: amount)!, currency: home, homeCurrency: home)
    }

    /// A rate-pending pair: the amount is known in its original currency (PLN)
    /// but the home (EUR) value is not resolved yet - the RV.106 shape.
    private static func pendingMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .pln, homeCurrency: .eur)
    }

    // MARK: - Fixture entry builders

    private static func fill(_ date: Date, amount: String, group: UUID?) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: 120_000,
            money: Self.homeMoney(amount, home: .eur), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            volumeL: 42, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private static func expense(_ date: Date, amount: String, group: UUID?,
                                home: CurrencyCode = .eur) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: Self.homeMoney(amount, home: home), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: "Wash", recurrence: nil,
            installedInServiceId: nil)
    }

    private static func pendingExpense(_ date: Date, amount: String, group: UUID?) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: Self.pendingMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: "Wash", recurrence: nil,
            installedInServiceId: nil)
    }

    // MARK: - The row's L1 fixtures

    /// The headline case: a receipt whose two known members total 30.00 EUR
    /// beside a third line still waiting on a rate. The honest figure is
    /// `30.00 EUR` MARKED partial with `pendingCount: 1` - never `30.00`
    /// presented as the group's total, and never the pending line summed as
    /// zero into a figure that reads as complete.
    @Test func groupWithKnownMembersAndAPendingMemberReportsPartialNotABareTotal() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "10.00", group: groupID),
            Self.expense(Self.date(2026, 8, 10, 9), amount: "20.00", group: groupID),
            Self.pendingExpense(Self.date(2026, 8, 10, 8), amount: "50.00", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        // The known members' own home amounts (10.00 + 20.00), to the cent; the
        // pending member contributes nothing because it HAS no home amount.
        let known = Decimal(string: "10.00")! + Decimal(string: "20.00")!
        #expect(group.total == LogStream.MonthTotal.partial(amount: known, currency: .eur,
                                                            pendingCount: 1))
        // The negative claims that make the shape a defect when violated: the
        // figure is never presented complete, and the pending line is never
        // summed as a zero that changes nothing.
        #expect(group.total != LogStream.MonthTotal.complete(amount: known, currency: .eur),
                "a bare 30.00 EUR must never read as the receipt's complete total")
        #expect(group.total != LogStream.MonthTotal.complete(amount: .zero, currency: .eur),
                "the pending line is not a zero-cost line")

        // Hard rule 4: the group is counted ONCE in the month divider - the
        // divider and the group header classify the same receipt identically
        // because both reduce its members through the shared accumulator.
        #expect(stream.sections[0].total == LogStream.MonthTotal.partial(
            amount: known, currency: .eur, pendingCount: 1))
    }

    /// An all-known group is unchanged from before RV.166: `.complete` with the
    /// exact sum, to the cent - the group header's old behaviour preserved.
    @Test func allKnownGroupReportsCompleteToTheCent() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "71.02", group: groupID),
            Self.expense(Self.date(2026, 8, 10, 9), amount: "8.00", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        #expect(group.total == LogStream.MonthTotal.complete(
            amount: Decimal(string: "79.02")!, currency: .eur))
        #expect(group.total != LogStream.MonthTotal.complete(
            amount: Decimal(string: "79.03")!, currency: .eur),
            "the sum must be exact, never a rounded or shifted figure")
    }

    /// A group whose KNOWN members span home currencies reports NO bare figure -
    /// today's `knownHome.count == 1` behaviour preserved: the known lines are a
    /// `.mixed` breakdown (RV.145), never a single cross-currency total (hard
    /// rule 3). A pending member on top keeps its own count.
    @Test func groupWhoseKnownMembersSpanCurrenciesReportsNoBareFigure() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "10.00", group: groupID),                       // home EUR
            Self.expense(Self.date(2026, 8, 10, 9), amount: "20.00", group: groupID,
                         home: .usd),                                               // home USD
            Self.pendingExpense(Self.date(2026, 8, 10, 8), amount: "50.00", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        // Largest subtotal first (the accumulator's stable display order).
        #expect(group.total == LogStream.MonthTotal.mixed(
            subtotals: [
                LogStream.SpendSubtotal(amount: Decimal(string: "20.00")!, currency: .usd),
                LogStream.SpendSubtotal(amount: Decimal(string: "10.00")!, currency: .eur)
            ],
            pendingCount: 1))
        // A mixed group has no single amount + currency pair to print bare.
        var isBare = false
        if case .complete = group.total { isBare = true }
        if case .partial = group.total { isBare = true }
        #expect(!isBare, "a receipt whose known lines span currencies must not state one total")
    }

    /// The group classifies through the shared seam: reducing its members'
    /// money pairs through `Accumulator` in the test yields exactly the
    /// classification the group carries - never a parallel sum that could drift.
    @Test func groupClassificationAgreesWithTheAccumulatorForTheSameMembers() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "68.46", group: groupID),
            Self.pendingExpense(Self.date(2026, 8, 10, 9), amount: "8.00", group: groupID),
            Self.pendingExpense(Self.date(2026, 8, 10, 8), amount: "9.50", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        var accumulator = LogStream.MonthTotal.Accumulator(vehicleHome: .eur)
        accumulator.add(contentsOf: group.members.map(\.money))
        #expect(group.total == accumulator.monthTotal)
        // The same seam also classifies the month divider over the same receipt.
        #expect(stream.sections[0].total == accumulator.monthTotal,
                "the divider must agree with the group header on the same members")
    }

    // MARK: - PJ.56 - the states a header must not stay silent about

    /// A receipt whose members are ALL rate-pending has no home figure at all:
    /// `.pending`, carrying the count the header and the divider both explain
    /// with - never a zero figure that reads as a free receipt. The month
    /// divider over the same members states the SAME count (the shared
    /// accumulator), so the header and the divider one row up say the same
    /// sentence (PJ.56).
    @Test func allPendingGroupReportsPendingAndTheDividerStatesTheSameCount() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.pendingExpense(month, amount: "71.02", group: groupID),
            Self.pendingExpense(Self.date(2026, 8, 10, 9), amount: "20.00", group: groupID),
            Self.pendingExpense(Self.date(2026, 8, 10, 8), amount: "8.00", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        #expect(group.total == LogStream.MonthTotal.pending(pendingCount: 3))
        #expect(group.total != LogStream.MonthTotal.complete(amount: .zero, currency: .eur),
                "an all-pending receipt must never read as a zero-cost receipt")
        // The divider over the same members carries the same count - the header
        // explains itself with the divider's own number (PJ.56).
        #expect(stream.sections[0].total == group.total,
                "the divider must state the same pending count as the group header")
    }

    /// A receipt whose known members span home currencies is `.mixed` for the
    /// group header exactly as for the divider over the same members - the two
    /// surfaces explain the same classification with the same per-currency
    /// subtotals, never one cross-currency total (hard rule 3, PJ.56).
    @Test func mixedGroupAndItsDividerStateTheSameBreakdown() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "71.02", group: groupID),                    // home EUR
            Self.expense(Self.date(2026, 8, 10, 9), amount: "20.00", group: groupID,
                         home: .eur),                                             // home EUR
            Self.expense(Self.date(2026, 8, 10, 8), amount: "8.00", group: groupID,
                         home: .usd)                                              // home USD
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        // Largest subtotal first (the accumulator's stable display order).
        let expected = LogStream.MonthTotal.mixed(
            subtotals: [
                LogStream.SpendSubtotal(amount: Decimal(string: "91.02")!, currency: .eur),
                LogStream.SpendSubtotal(amount: Decimal(string: "8.00")!, currency: .usd)
            ],
            pendingCount: 0)
        #expect(group.total == expected)
        // The divider over the same members cannot disagree with the header.
        #expect(stream.sections[0].total == group.total,
                "the divider must state the same breakdown as the group header")
    }
}
