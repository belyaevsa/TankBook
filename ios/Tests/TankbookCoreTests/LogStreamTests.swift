import Testing
import Foundation
@testable import TankbookCore

/// The Log stream's derived decisions (docs/DESIGN.md -> "Entry card content";
/// docs/SCHEMA.md -> CHECK 3): ordering, month grouping with divider totals,
/// purchase-group rendering, the fuel-kind visibility rule, odometer omission,
/// and the collapse contract. All pure - no simulator needed (docs/TESTING.md,
/// L1).
struct LogStreamTests {

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

    private static func vehicle(fuelKinds: [FuelKind] = [.petrol95, .diesel]) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.date(2025, 6, 1), updatedAt: Self.date(2025, 6, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: fuelKinds,
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func money(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    // MARK: - Fixture entry builders

    private static func fill(_ date: Date, odometer: Int? = 120_000, litres: Double = 42,
                             amount: String = "71.02", kind: FuelKind = .petrol95,
                             stationID: UUID? = nil, group: UUID? = nil,
                             attachments: [AttachmentID] = [],
                             conflict: ConflictState = .none) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Self.money(amount), note: nil, attachments: attachments,
            provenance: .manual, conflict: conflict, purchaseGroupId: group,
            volumeL: litres, unitPrice: nil, fuelKind: kind, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: stationID,
            crossCheck: .verified, extraction: nil)
    }

    private static func charge(_ date: Date, odometer: Int? = 120_000,
                               amount: String = "21.50", attachments: [AttachmentID] = []) -> ChargeSession {
        ChargeSession(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Self.money(amount), note: nil, attachments: attachments,
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            energyKWh: 38, unitPrice: nil, chargeType: .dcPublic, provider: "Ionity",
            tariffId: nil, durationMin: nil, socStartPct: nil, socEndPct: nil,
            extraction: nil)
    }

    private static func service(_ date: Date, odometer: Int? = 119_000,
                                amount: String = "148.00") -> ServiceRecord {
        ServiceRecord(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Self.money(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            vendor: "Bosch Service", items: [], usedParts: [], tireSetId: nil,
            proposedReminderId: nil)
    }

    private static func expense(_ date: Date, odometer: Int? = nil,
                                amount: String = "6.00", title: String = "Parking",
                                group: UUID? = nil,
                                attachments: [AttachmentID] = []) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Self.money(amount), note: nil, attachments: attachments,
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: title, recurrence: nil,
            installedInServiceId: nil)
    }

    // MARK: - Ordering: the union interleaves by date, newest first

    @Test func unionInterleavesEntryTypesByDateDescending() {
        let dates: [Date] = [
            Self.date(2025, 6, 30), Self.date(2025, 7, 15), Self.date(2025, 7, 20),
            Self.date(2025, 8, 1), Self.date(2025, 8, 31)
        ]
        let entries: [any Entry] = [
            Self.fill(dates[0]),
            Self.service(dates[1]),
            Self.charge(dates[2]),
            Self.fill(dates[3]),
            Self.expense(dates[4])
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)

        let flat = stream.allRows.map { $0.date }
        #expect(flat == [dates[4], dates[3], dates[2], dates[1], dates[0]])
    }

    @Test func createdAtBreaksDateTies() {
        let sameDay = Self.date(2025, 8, 1)
        let earlier = Self.fill(sameDay)
        var later = Self.fill(sameDay)
        later.createdAt = sameDay.addingTimeInterval(60)
        let stream = LogStream(vehicle: Self.vehicle(), entries: [earlier, later], calendar: Self.calendar)
        #expect(stream.allRows.map(\.id) == [later.id, earlier.id])
    }

    // MARK: - Month grouping

    @Test func threeMonthsProduceThreeDividersEachHoldingItsOwnMonth() {
        let jun = Self.date(2025, 6, 5)
        let jul = Self.date(2025, 7, 10)
        let aug = Self.date(2025, 8, 15)
        let stream = LogStream(vehicle: Self.vehicle(),
                               entries: [Self.fill(aug), Self.expense(jul), Self.fill(jun)],
                               calendar: Self.calendar)

        #expect(stream.sections.count == 3)
        let monthStarts = stream.sections.map { Self.calendar.component(.month, from: $0.monthStart) }
        #expect(monthStarts == [8, 7, 6])
        // Each divider holds only its own month's rows, newest first.
        #expect(stream.sections[0].rows.map(\.date) == [aug])
        #expect(stream.sections[1].rows.map(\.date) == [jul])
        #expect(stream.sections[2].rows.map(\.date) == [jun])
    }

    @Test func monthBoundaryAtFirstAndThirtyFirstLandsInTheRightGroup() {
        let july31 = Self.date(2025, 7, 31)
        let aug1 = Self.date(2025, 8, 1)
        let stream = LogStream(vehicle: Self.vehicle(), entries: [Self.fill(aug1), Self.expense(july31)],
                               calendar: Self.calendar)
        #expect(stream.sections.count == 2)
        #expect(stream.sections[0].rows.map(\.date) == [aug1])
        #expect(stream.sections[1].rows.map(\.date) == [july31])
    }

    // MARK: - Divider totals

    @Test func dividerTotalSumsEveryEntryType() {
        let month = Self.date(2025, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "68.46"),          // fuel
            Self.charge(month, amount: "21.50"),        // charge
            Self.service(month, amount: "148.00"),      // service
            Self.expense(month, amount: "6.00")        // expense
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        #expect(stream.sections.count == 1)
        #expect(stream.sections[0].totalSpend
                == Decimal(string: "68.46")! + Decimal(string: "21.50")!
                   + Decimal(string: "148.00")! + Decimal(string: "6.00")!)
    }

    @Test func dividerTotalCountsAGroupGrandTotalOnceNotPerMember() {
        // One physical purchase: a fill at 71.02 plus a car wash at 8.00 from
        // the same receipt. The group's grand total (79.02) is one number.
        let groupID = UUID.v7()
        let month = Self.date(2025, 8, 10)
        let entries: [any Entry] = [
            Self.fill(month, amount: "71.02", group: groupID),
            Self.expense(month, amount: "8.00", title: "Car wash", group: groupID),
            Self.service(month, amount: "148.00"),       // standalone
            Self.fill(month, amount: "68.46")           // standalone
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)

        let standalone = Decimal(string: "148.00")! + Decimal(string: "68.46")!
        let grandTotal = Decimal(string: "71.02")! + Decimal(string: "8.00")!
        #expect(stream.sections[0].totalSpend == standalone + grandTotal)

        // The trap from hard rule 4 / CHECK 3: the fill's amount alone is NOT
        // the purchase total, and the group is not counted once per member.
        #expect(stream.sections[0].totalSpend != standalone + Decimal(string: "71.02")!)
        #expect(stream.sections[0].totalSpend != standalone + grandTotal * 2)
    }

    // MARK: - Fuel-kind visibility (docs/DESIGN.md)

    @Test func fuelKindHiddenForSingleFuelVehicleWithUsualKind() {
        let single = Self.vehicle(fuelKinds: [.petrol95])
        let entry = LogStream(vehicle: single,
                              entries: [Self.fill(Self.date(2025, 8, 10), kind: .petrol95)],
                              calendar: Self.calendar).allRows[0]
        guard case .entry(let logEntry) = entry else {
            Issue.record("expected an entry row")
            return
        }
        #expect(logEntry.showsFuelKind == false)
        #expect(!logEntry.subtitleSegments.contains { $0.showsFuelKind })
    }

    @Test func fuelKindShownForMultiFuelVehicle() {
        let multi = Self.vehicle(fuelKinds: [.petrol95, .diesel])
        let entry = LogStream(vehicle: multi,
                              entries: [Self.fill(Self.date(2025, 8, 10), kind: .petrol95)],
                              calendar: Self.calendar).allRows[0]
        guard case .entry(let logEntry) = entry else {
            Issue.record("expected an entry row")
            return
        }
        #expect(logEntry.showsFuelKind == true)
        #expect(logEntry.subtitleSegments.contains { $0.showsFuelKind })
    }

    @Test func fuelKindShownWhenItDiffersFromTheCarsUsual() {
        let petrolOnly = Self.vehicle(fuelKinds: [.petrol95])
        let dieselFill = Self.fill(Self.date(2025, 8, 10), kind: .diesel)
        let entry = LogStream(vehicle: petrolOnly, entries: [dieselFill],
                              calendar: Self.calendar).allRows[0]
        guard case .entry(let logEntry) = entry else {
            Issue.record("expected an entry row")
            return
        }
        #expect(logEntry.showsFuelKind == true)
        #expect(logEntry.subtitleSegments.contains { $0.isDiesel })
    }

    // MARK: - Odometer segment

    @Test func odometerSegmentOmittedWhenTheEntryHasNone() {
        let noOdo = Self.expense(Self.date(2025, 8, 10), odometer: nil)
        let entry = LogStream(vehicle: Self.vehicle(), entries: [noOdo],
                              calendar: Self.calendar).allRows[0]
        guard case .entry(let logEntry) = entry else {
            Issue.record("expected an entry row")
            return
        }
        #expect(logEntry.odometer == nil)
        #expect(!logEntry.subtitleSegments.contains { $0.showsOdometer })
    }

    @Test func odometerSegmentPresentWhenTheEntryHasOne() {
        let withOdo = Self.fill(Self.date(2025, 8, 10), odometer: 119_486)
        let entry = LogStream(vehicle: Self.vehicle(), entries: [withOdo],
                              calendar: Self.calendar).allRows[0]
        guard case .entry(let logEntry) = entry else {
            Issue.record("expected an entry row")
            return
        }
        #expect(logEntry.subtitleSegments.contains { $0.odometerAt119486 })
    }

    // MARK: - Collapse contract

    @Test func collapsedGroupReportsOneRowExpandedReportsItsMembers() {
        let groupID = UUID.v7()
        let month = Self.date(2025, 8, 10)
        let stream = LogStream(
            vehicle: Self.vehicle(),
            entries: [
                Self.fill(month, amount: "71.02", group: groupID),
                Self.expense(month, amount: "8.00", title: "Car wash", group: groupID),
                Self.expense(month, amount: "6.00")   // standalone
            ],
            calendar: Self.calendar)

        // 3 rows: 2 group members (expanded) + 1 standalone.
        #expect(stream.rowCount(collapsedGroupIDs: []) == 3)
        // Collapse the group: it reports ONE row, so 2 total.
        #expect(stream.rowCount(collapsedGroupIDs: [groupID]) == 2)
        // A different group id does not collapse this one.
        #expect(stream.rowCount(collapsedGroupIDs: [UUID.v7()]) == 3)
    }

    @Test func groupMembersAreSortedNewestFirstAndShareOneGrandTotal() {
        let groupID = UUID.v7()
        let wash = Self.expense(Self.date(2025, 8, 10, 9), amount: "8.00", title: "Car wash", group: groupID)
        var fuel = Self.fill(Self.date(2025, 8, 10), amount: "71.02", group: groupID)
        fuel.createdAt = Self.date(2025, 8, 10, 8)
        let stream = LogStream(vehicle: Self.vehicle(), entries: [fuel, wash],
                               calendar: Self.calendar)
        guard case .group(let group) = stream.allRows[0] else {
            Issue.record("expected a group row")
            return
        }
        #expect(group.grandTotal == Decimal(string: "79.02"))
        // Newest first: the fill (hour 12) sits above the wash (hour 9).
        #expect(group.members.map(\.kind) == [.fuel, .expense])
    }
}

/// Display-decision helpers for the subtitle-segment assertions - the checks
/// read as intent ("shows fuel kind") instead of an inline pattern match.
private extension LogStream.SubtitleSegment {
    var showsFuelKind: Bool {
        if case .fuelKind = self { return true }
        return false
    }

    var isDiesel: Bool {
        if case .fuelKind(.diesel) = self { return true }
        return false
    }

    var showsOdometer: Bool {
        if case .odometer = self { return true }
        return false
    }

    var odometerAt119486: Bool {
        if case .odometer(119_486) = self { return true }
        return false
    }
}
