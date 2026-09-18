import Foundation
import Testing
@testable import TankbookCore

/// RV.120: the fill pattern. The absent cases are the design - a car with one
/// fill, an uncorroborated tank capacity, a month too young to forecast, a car
/// under the floor - so each is pinned beside the arithmetic.
struct FillPatternTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2026-03-15 12:00 UTC - day 15 of a 31-day month.
    private static let asOf = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
    private static let day: TimeInterval = 86_400

    private static func vehicle(tankCapacityL: Double?) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: asOf - 400 * day, updatedAt: asOf - 400 * day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: tankCapacityL, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 100_000)
    }

    private static func fill(daysAgo: Int, odometer: Int, litres: Double, amount: String = "60",
                             isFull: Bool = true) -> FillUp {
        let date = asOf - Double(daysAgo) * day
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: litres, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: isFull,
            tankLevelAfterPct: isFull ? 100 : nil, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    /// Four full fills every 10 days, 500 km apart, 40 L each: 8.0 L/100km.
    private static let steady = [
        fill(daysAgo: 40, odometer: 100_000, litres: 40, amount: "50"),
        fill(daysAgo: 30, odometer: 100_500, litres: 40, amount: "50"),
        fill(daysAgo: 20, odometer: 101_000, litres: 40, amount: "50"),
        fill(daysAgo: 10, odometer: 101_500, litres: 40, amount: "50")
    ]

    private static func pattern(_ fills: [FillUp], capacity: Double? = 50) -> FillPattern? {
        HomeStats(vehicle: vehicle(tankCapacityL: capacity), entries: fills, asOf: asOf, calendar: calendar).fillPattern
    }

    @Test("distance between fills and frequency match the fixture; absent for one fill and under the floor")
    func spacingAndFrequency() {
        let pattern = Self.pattern(Self.steady)
        #expect(pattern?.kmBetweenFills == 500)
        #expect(pattern?.daysBetweenFills == 10)
        #expect(Self.pattern([Self.steady[0]]) == nil, "under the floor there is no pattern at all")
        #expect(Self.pattern([Self.steady[0], Self.steady[1]])?.kmBetweenFills == 500,
                "a first estimate still measures the spacing it has")
    }

    @Test("range left needs a corroborated capacity, and is the arithmetic when it has one")
    func rangeLeft() {
        // 50 L stated; the 40 L fills corroborate it (≥ 80%). 8.0 L/100km ->
        // a 625 km tank; the last full fill was at 101 500 and the odometer is
        // 101 500 (the latest entry), so the whole tank is left.
        #expect(Self.pattern(Self.steady, capacity: 50)?.rangeLeftKm == 625)
        // A 90 L catalog figure nobody ever filled to 72 L: absent, never a
        // guess - the same fills, the same consumption.
        #expect(Self.pattern(Self.steady, capacity: 90)?.rangeLeftKm == nil)
        #expect(Self.pattern(Self.steady, capacity: nil)?.rangeLeftKm == nil)
        // A fill above the stated capacity refutes it.
        let refuted = Self.steady + [Self.fill(daysAgo: 5, odometer: 101_900, litres: 55, amount: "60")]
        #expect(!FillPattern.capacityIsCorroborated(50, fills: refuted))
        // Distance driven since the last full fill comes off the tank range.
        let driven = Self.steady + [Self.fill(daysAgo: 2, odometer: 101_800, litres: 10, amount: "12", isFull: false)]
        #expect(Self.pattern(driven, capacity: 50)?.rangeLeftKm == 625 - 300)
    }

    @Test("the forecast is the stated method - spend so far scaled to the month - and absent too early or too thin")
    func forecast() {
        // Day 15 of 31, two fills this month (days 10 and 5 ago): 100 € so far.
        let thisMonth = Self.steady + [Self.fill(daysAgo: 5, odometer: 102_000, litres: 40, amount: "50")]
        let pattern = Self.pattern(thisMonth)
        // 100 / 15 * 31 = 206.67 -> 207.
        #expect(pattern?.monthForecast == FillPattern.MonthForecast(amount: 207, currency: .eur, daysElapsed: 15))

        // One fill this month: no pace to speak of.
        #expect(Self.pattern(Self.steady)?.monthForecast == nil)

        // Day 3 of the month: too early, whatever the fills.
        let early = Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 12))!
        let earlyStats = HomeStats(vehicle: Self.vehicle(tankCapacityL: 50),
                                   entries: [Self.fill(daysAgo: 1, odometer: 101_600, litres: 40)] + Self.steady,
                                   asOf: early, calendar: Self.calendar)
        #expect(earlyStats.fillPattern?.monthForecast == nil)
    }
}
