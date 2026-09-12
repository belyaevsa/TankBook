import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.56 L1 - a purchase-group header that must never stay silent where the
/// month divider over the same members already speaks. The seams under test are
/// the ones `groupTotalFigure` renders through (`HomeFormat.groupFigure` /
/// `HomeFormat.groupPendingNote`), so a `.pending` header states the divider's
/// own phrase and a `.mixed` header states the divider's own per-currency
/// breakdown - asserted from the shared `MonthTotal` classification, never a
/// parallel count or sum written in the test.
final class PJ56GroupHeaderTextTests: XCTestCase {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private func vehicle() -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: date(1), updatedAt: date(1),
                deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60",
                year: 2015, plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
                tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l,
                                     consumption: .lPer100, energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500,
                initialOdometer: 118_000)
    }

    private func expense(_ date: Date, amount: String, group: UUID,
                         vehicleID: UUID, home: CurrencyCode = .eur,
                         pending: Bool = false) -> Expense {
        let money: Money = pending
            ? Money(amount: decimal(amount), currency: .pln, homeCurrency: .eur)
            : Money(amount: decimal(amount), currency: home, homeCurrency: home)
        return Expense(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                       vehicleId: vehicleID, date: date, odometer: nil,
                       money: money, note: nil, attachments: [], provenance: .manual,
                       conflict: .none, purchaseGroupId: group,
                       category: .parking, title: "Wash",
                       installedInServiceId: nil)
    }

    // MARK: - .pending: the header states the divider's own phrase

    /// The headline case (PJ.56): an all-pending receipt is `.pending` for the
    /// group header AND for the month divider over the same members, so the
    /// header's explanation is the divider's own phrase - `L10n.pendingRates`
    /// on the count the shared total carries, never an empty figure slot.
    func testPendingGroupHeaderStatesThePendingPhraseTheDividerStates() {
        let car = vehicle()
        let groupID = UUID.v7()
        let entries: [any Entry] = [
            expense(date(10), amount: "71.02", group: groupID, vehicleID: car.id,
                    pending: true),
            expense(date(10, 9), amount: "20.00", group: groupID, vehicleID: car.id,
                    pending: true)
        ]
        let stream = LogStream(vehicle: car, entries: entries, calendar: calendar)
        guard case .group(let group) = stream.allRows[0] else {
            return XCTFail("expected a group row")
        }
        // The divider over the same members classifies identically - the shared
        // seam the whole claim rests on (no parallel member count here).
        XCTAssertEqual(group.total, LogStream.MonthTotal.pending(pendingCount: 2))
        XCTAssertEqual(stream.sections[0].total, group.total,
                       "the divider and the group header must agree on the same members")

        // The header has no figure to print and says so with the pending phrase.
        XCTAssertNil(HomeFormat.groupFigure(group.total),
                     "an all-pending receipt has no home figure to state")
        guard case .pending(let count) = stream.sections[0].total else {
            return XCTFail("expected the divider to be pending")
        }
        XCTAssertEqual(HomeFormat.groupPendingNote(group.total),
                       L10n.pendingRates(count),
                       "the group header must explain itself with the divider's own phrase")
    }

    // MARK: - .complete / .partial unchanged to the cent (RV.166)

    func testCompleteGroupFigureIsUnchangedToTheCent() {
        XCTAssertEqual(HomeFormat.groupFigure(
            .complete(amount: decimal("79.02"), currency: .eur)),
            "79.02\u{00A0}€")
        XCTAssertNil(HomeFormat.groupPendingNote(
            .complete(amount: decimal("79.02"), currency: .eur)))
    }

    func testPartialGroupFigureIsUnchangedAndMarkedWithThePendingPhrase() {
        let total = LogStream.MonthTotal.partial(amount: decimal("30.00"),
                                                 currency: .eur, pendingCount: 1)
        XCTAssertEqual(HomeFormat.groupFigure(total), "30.00\u{00A0}€")
        XCTAssertEqual(HomeFormat.groupPendingNote(total), L10n.pendingRates(1))
    }

    // MARK: - .mixed: the per-currency breakdown, never a summed total

    /// The negative claim that keeps the fix from becoming a hard rule 3
    /// violation: a receipt whose known members span home currencies renders
    /// EACH figure under its own symbol (the divider's breakdown vocabulary),
    /// and the sum across currencies never appears.
    func testMixedGroupHeaderStatesTheBreakdownNeverACrossCurrencyTotal() {
        let total = LogStream.MonthTotal.mixed(
            subtotals: [.init(amount: decimal("91.02"), currency: .eur),
                        .init(amount: decimal("8.00"), currency: .usd)],
            pendingCount: 0)
        XCTAssertEqual(HomeFormat.groupFigure(total), "91.02\u{00A0}€ · 8.00\u{00A0}$")
        let figure = HomeFormat.groupFigure(total)!
        XCTAssertTrue(figure.contains("€"), "the breakdown carries each currency's own symbol")
        XCTAssertTrue(figure.contains("$"), "the breakdown carries each currency's own symbol")
        XCTAssertFalse(figure.contains("99.02"),
                       "the header must never print the cross-currency sum, got \(figure)")
        XCTAssertNil(HomeFormat.groupPendingNote(total),
                     "a mixed receipt whose members all converted needs no pending note")
    }

    func testMixedGroupWithWaitingMemberCarriesThePendingPhraseBeneathTheBreakdown() {
        let total = LogStream.MonthTotal.mixed(
            subtotals: [.init(amount: decimal("91.02"), currency: .eur),
                        .init(amount: decimal("8.00"), currency: .usd)],
            pendingCount: 2)
        XCTAssertEqual(HomeFormat.groupPendingNote(total), L10n.pendingRates(2),
                       "a mixed receipt that still waits carries the divider's pending phrase")
    }
}
