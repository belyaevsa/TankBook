import Testing
import Foundation
@testable import TankbookCore

/// RV.106 - a month whose rates have not arrived must not report "0 €".
///
/// The divider-honesty tests live in their own suite (and file) so
/// `LogStreamTests` stays under the lint body-length ceiling. Same fixtures,
/// same builders - self-contained so the two suites never share private state.
///
/// The claims: a month whose rows are ALL rate-pending is `.pending` (never a
/// `.complete(0)` - the owner's "0 €" was a wrong number, not a missing one,
/// hard rule 2); a MIXED month reports the exact known sum marked `.partial`;
/// a fully-converted month is `.complete` to the cent; and the purchase-group
/// and duplicate arms of the divider follow the entry arm's rule so no shape
/// silently under-counts a pending row.
struct LogStreamDividerRatePendingTests {

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
    /// but the home (EUR) value is not resolved yet - the RV.106 shape.
    private static func pendingMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .pln, homeCurrency: .eur)
    }

    // MARK: - Fixture entry builders

    private static func fill(_ date: Date, odometer: Int? = 120_000,
                             amount: String, group: UUID? = nil,
                             vehicleID: UUID = UUID.v7()) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odometer,
            money: Self.homeMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            volumeL: 42, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private static func pendingFill(_ date: Date, odometer: Int? = 120_000,
                                    amount: String, group: UUID? = nil,
                                    vehicleID: UUID = UUID.v7()) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odometer,
            money: Self.pendingMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            volumeL: 42, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private static func expense(_ date: Date, amount: String,
                                group: UUID? = nil) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: Self.homeMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: "Parking", recurrence: nil,
            installedInServiceId: nil)
    }

    private static func pendingExpense(_ date: Date, amount: String,
                                       group: UUID? = nil) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: Self.pendingMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: "Parking", recurrence: nil,
            installedInServiceId: nil)
    }

    private static func service(_ date: Date, amount: String) -> ServiceRecord {
        ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: 119_000,
            money: Self.homeMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            vendor: "Bosch Service", items: [], usedParts: [], tireSetId: nil)
    }

    // MARK: - The three fixtures the row's L1 demands

    /// The owner's actual case: a month whose rows are ALL still waiting on a
    /// rate must NOT report `0 €` - there is no home figure, so the divider
    /// says so instead of asserting a spend the user did not have (hard rule 2).
    /// Asserted as the model, never as "not zero": the vacuous trap is a wrong
    /// non-zero number passing an "isn't zero" check.
    @Test func allPendingMonthReportsPendingNotAZeroTotal() {
        let month = Self.date(2026, 6, 10)
        let entries: [any Entry] = [
            Self.pendingFill(month, amount: "107.25"),
            Self.pendingFill(Self.date(2026, 6, 15), amount: "101.71"),
            Self.pendingFill(Self.date(2026, 6, 20), amount: "112.06"),
            Self.pendingExpense(Self.date(2026, 6, 22), amount: "8.00")
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        #expect(stream.sections.count == 1)
        #expect(stream.sections[0].total == LogStream.MonthTotal.pending(pendingCount: 4))
        #expect(stream.sections[0].total != LogStream.MonthTotal.complete(amount: .zero, currency: .eur),
                "an all-pending month must never be reported as a zero spend")
    }

    /// A MIXED month - some rows converted, some still waiting - must report
    /// the known sum EXACTLY (to the cent) and mark it partial with the count
    /// of what is missing, never a bare total that reads as complete.
    @Test func mixedMonthReportsTheKnownSumAsPartial() {
        let month = Self.date(2026, 7, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "68.46"),                           // converted (EUR)
            Self.pendingFill(Self.date(2026, 7, 12), amount: "289.50"),  // pending (PLN)
            Self.service(Self.date(2026, 7, 15), amount: "148.00"),      // converted
            Self.pendingFill(Self.date(2026, 7, 18), amount: "294.00")   // pending
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        #expect(stream.sections.count == 1)
        // The partial figure is the sum of the CONVERTED rows only, to the
        // cent - never the pending rows' zero-filled contribution, never
        // today's rate on them (RV.88).
        let known = Decimal(string: "68.46")! + Decimal(string: "148.00")!
        #expect(stream.sections[0].total == LogStream.MonthTotal.partial(amount: known,
                                                                         currency: .eur,
                                                                         pendingCount: 2))
    }

    /// A fully-converted month is unchanged in behaviour from before RV.106:
    /// `.complete` with the exact sum, to the cent.
    @Test func fullyConvertedMonthReportsCompleteToTheCent() {
        let month = Self.date(2026, 8, 10)
        let stream = LogStream(vehicle: Self.vehicle(),
                               entries: [Self.fill(month, amount: "107.25"),
                                         Self.fill(Self.date(2026, 8, 20), amount: "101.71")],
                               calendar: Self.calendar)
        #expect(stream.sections[0].total
                == LogStream.MonthTotal.complete(amount: Decimal(string: "107.25")! + Decimal(string: "101.71")!,
                                                 currency: .eur))
    }

    // MARK: - The purchase-group and duplicate arms (the same reduce)

    /// A purchase group whose receipt mixes a converted line with a rate-pending
    /// one is PARTIAL, exactly like a mixed month of standalone entries - the
    /// group arm of the divider must not disagree with the entry arm.
    @Test func groupWithPendingMemberReportsPartial() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 7, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "71.02", group: groupID),
            Self.pendingExpense(Self.date(2026, 7, 10, 9), amount: "8.00", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        #expect(stream.sections.count == 1)
        #expect(stream.sections[0].total == LogStream.MonthTotal.partial(
            amount: Decimal(string: "71.02")!, currency: .eur, pendingCount: 1))
    }

    /// A group whose members are ALL rate-pending has no known figure: pending.
    @Test func allPendingGroupReportsPending() {
        let groupID = UUID.v7()
        let month = Self.date(2026, 7, 10)
        let entries: [any Entry] = [
            Self.pendingFill(month, amount: "71.02", group: groupID),
            Self.pendingExpense(Self.date(2026, 7, 10, 9), amount: "8.00", group: groupID)
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        #expect(stream.sections[0].total == LogStream.MonthTotal.pending(pendingCount: 2))
    }

    /// An unresolved S2 pair whose COUNTED entry is rate-pending is pending
    /// (only the counted member ever counts - docs/SYNC.md S2).
    @Test func duplicateWithPendingCountedEntryReportsPending() {
        let month = Self.date(2026, 7, 10)
        let vehicleID = UUID.v7()
        // Two near-identical fills -> an unresolved pair. The detector counts
        // the earlier-created member; build both pending so whichever counts,
        // the month is pending.
        let first = Self.pendingFill(month, amount: "71.02", vehicleID: vehicleID)
        var second = Self.pendingFill(month, amount: "72.05", vehicleID: vehicleID)
        second.createdAt = month.addingTimeInterval(900)
        let stream = LogStream(vehicle: Self.vehicle(), entries: [first, second], calendar: Self.calendar)
        #expect(stream.allRows.count == 1, "the unresolved pair renders as ONE card")
        #expect(stream.sections[0].total == LogStream.MonthTotal.pending(pendingCount: 1))
    }

    /// An unresolved S2 pair whose counted entry is converted stays COMPLETE
    /// even when the excluded member is pending - the excluded member's state
    /// never leaks into the divider (S2: it never counts anywhere).
    @Test func duplicateWithConvertedCountedEntryStaysCompleteWhenExcludedIsPending() {
        let month = Self.date(2026, 7, 10)
        let vehicleID = UUID.v7()
        // The detector counts the EARLIER-created member (the converted one).
        let counted = Self.fill(month, amount: "71.02", vehicleID: vehicleID)
        var excluded = Self.pendingFill(month, amount: "72.05", vehicleID: vehicleID)
        excluded.createdAt = month.addingTimeInterval(900)
        let stream = LogStream(vehicle: Self.vehicle(), entries: [counted, excluded], calendar: Self.calendar)
        #expect(stream.sections[0].total == LogStream.MonthTotal.complete(amount: Decimal(string: "71.02")!,
                                                                          currency: .eur))
    }
}
