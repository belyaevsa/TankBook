import Foundation
import Testing
@testable import TankbookCore

/// RV.119: the month divider's glance. Two complete months on purpose (one
/// month can never be compared), the rows' arithmetic checked to the unit,
/// and the incomparable months - partial, rate-pending, one fill, the month
/// in progress - yielding NO delta.
struct MonthGlanceTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: date(2025, 1, 1), updatedAt: date(2025, 1, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: nil, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 100_000)
    }

    private static func fill(_ date: Date, odometer: Int, litres: Double, amount: String,
                             isFull: Bool = true, pending: Bool = false) -> FillUp {
        let money = pending
            ? Money(amount: Decimal(string: amount)!, currency: .usd, homeCurrency: .eur)
            : Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer, money: money,
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: litres, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: isFull,
            tankLevelAfterPct: isFull ? 100 : nil, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    private static func glance(_ stream: LogStream, _ year: Int, _ month: Int) -> MonthGlance? {
        stream.sections.first { $0.monthStart == date(year, month, 1).addingTimeInterval(-12 * 3600) }?.glance
    }

    @Test("distance, consumption and cost per km match the rows beneath the divider")
    func figuresMatchTheRows() {
        // December: 100 000 -> 101 000 km, the closing fills 40 + 45 L over
        // the two segments (600 + 400 km), 100.00 + 80.00 €.
        // January's rows span 101 600 -> 102 200 km (the distance is between the
        // month's OWN readings); its one closing segment runs from December's
        // last full fill, 1 200 km on 20 + 28 L; spend 96 + 60 €.
        let entries: [any Entry] = [
            Self.fill(Self.date(2025, 12, 2), odometer: 100_000, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2025, 12, 12), odometer: 100_600, litres: 40, amount: "80.00"),
            Self.fill(Self.date(2025, 12, 22), odometer: 101_000, litres: 45, amount: "90.00"),
            Self.fill(Self.date(2026, 1, 10), odometer: 101_600, litres: 20, amount: "96.00", isFull: false),
            Self.fill(Self.date(2026, 1, 25), odometer: 102_200, litres: 28, amount: "60.00")
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar,
                               asOf: Self.date(2026, 3, 15))
        let december = try? #require(Self.glance(stream, 2025, 12))
        #expect(december?.distanceKm == 1_000)
        // Segments closing in December: 600 km / 40 L and 400 km / 45 L.
        #expect(december?.per100.map { ($0 * 10).rounded() / 10 } == 8.5)
        #expect(december?.costPerKm?.amount == Decimal(string: "270.00"))
        #expect(december?.costPerKm.map { ($0.perKm * 100).rounded() / 100 } == 0.27)
        #expect(december?.spendDelta == nil, "nothing before December to compare against")

        let january = try? #require(Self.glance(stream, 2026, 1))
        #expect(january?.distanceKm == 600)
        // One segment closes in January: 101 000 -> 102 200 on 20 + 28 L.
        #expect(january?.per100 == 4.0)
        // 156 € against December's 270 €: -42%, across the year boundary.
        #expect(january?.spendDelta?.percent == -42)
        #expect(january?.spendDelta?.previousMonthStart == Self.date(2025, 12, 1).addingTimeInterval(-12 * 3600))
    }

    @Test("a pending, partial, one-fill or in-progress month has no delta; a higher month says so")
    func incomparableMonths() {
        let asOf = Self.date(2026, 3, 15)
        // February has one fill - compared against nothing, and March (in
        // progress) is never compared even though February is complete.
        let base: [any Entry] = [
            Self.fill(Self.date(2026, 1, 5), odometer: 100_000, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2026, 1, 20), odometer: 100_500, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2026, 2, 10), odometer: 101_000, litres: 40, amount: "150.00"),
            Self.fill(Self.date(2026, 3, 3), odometer: 101_500, litres: 40, amount: "50.00"),
            Self.fill(Self.date(2026, 3, 9), odometer: 102_000, litres: 40, amount: "50.00")
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: base, calendar: Self.calendar, asOf: asOf)
        #expect(Self.glance(stream, 2026, 2)?.spendDelta == nil, "one fill is not a month to compare")
        #expect(Self.glance(stream, 2026, 3)?.spendDelta == nil, "the month in progress is never compared")
        #expect(Self.glance(stream, 2026, 2)?.distanceKm == nil, "one odometer reading spans nothing")

        // A rate-pending row makes February partial: no delta for March either
        // way, and none for February against January.
        let pending: [any Entry] = [
            Self.fill(Self.date(2026, 1, 5), odometer: 100_000, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2026, 1, 20), odometer: 100_500, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2026, 2, 10), odometer: 101_000, litres: 40, amount: "150.00"),
            Self.fill(Self.date(2026, 2, 20), odometer: 101_400, litres: 40, amount: "150.00", pending: true)
        ]
        let pendingStream = LogStream(vehicle: Self.vehicle(), entries: pending, calendar: Self.calendar, asOf: asOf)
        let february = Self.date(2026, 2, 1).addingTimeInterval(-12 * 3600)
        guard case .partial? = pendingStream.sections.first { $0.monthStart == february }?.total else {
            Issue.record("February must be partial with a rate-pending row")
            return
        }
        #expect(Self.glance(pendingStream, 2026, 2)?.spendDelta == nil, "a partial month has no honest delta")
        #expect(Self.glance(pendingStream, 2026, 2)?.costPerKm == nil, "nor an honest cost per km")

        // Two complete months, the later one higher: +50%.
        let higher: [any Entry] = [
            Self.fill(Self.date(2025, 11, 5), odometer: 100_000, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2025, 11, 20), odometer: 100_500, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2025, 12, 10), odometer: 101_000, litres: 40, amount: "150.00"),
            Self.fill(Self.date(2025, 12, 20), odometer: 101_400, litres: 40, amount: "150.00")
        ]
        let higherStream = LogStream(vehicle: Self.vehicle(), entries: higher, calendar: Self.calendar, asOf: asOf)
        #expect(Self.glance(higherStream, 2025, 12)?.spendDelta?.percent == 50)
    }

    @Test("a preview cut carries no glance - a partial month is never summed into one")
    func previewHasNoGlance() {
        let entries: [any Entry] = [
            Self.fill(Self.date(2025, 12, 2), odometer: 100_000, litres: 40, amount: "100.00"),
            Self.fill(Self.date(2025, 12, 12), odometer: 100_600, litres: 40, amount: "80.00"),
            Self.fill(Self.date(2025, 12, 22), odometer: 101_000, litres: 45, amount: "90.00")
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar,
                               asOf: Self.date(2026, 3, 15))
        #expect(stream.sections.first?.glance != nil)
        #expect(stream.previewRows(2).sections.first?.glance == nil)
    }
}
