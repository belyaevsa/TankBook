import Testing
import Foundation
@testable import TankbookCore

/// The hero tile's arrow (docs/JOURNEYS.md J8): the current window's headline
/// against the window of the same length before it. The property under test
/// is the abstention rule - an arrow exists only when BOTH windows stand on
/// their own segments and the move clears the noise threshold; every other
/// shape is `nil`, never a fabricated direction.
struct HeadlineChangeTests {

    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    /// A segment closing `daysAgo` at `per100` over 500 km.
    private func segment(daysAgo: Double, per100: Double) -> Segment {
        Segment(closes: Self.asOf - daysAgo * Self.day, km: 500, litres: per100 * 5,
                openingFillID: UUID.v7(), closingFillID: UUID.v7())
    }

    @Test("three segments in each window: the arrow and its size come from the two headlines")
    func twoFullWindowsYieldTheChange() throws {
        let segments = [
            segment(daysAgo: 10, per100: 6.0), segment(daysAgo: 40, per100: 6.0), segment(daysAgo: 70, per100: 6.0),
            segment(daysAgo: 100, per100: 7.5), segment(daysAgo: 130, per100: 7.5), segment(daysAgo: 160, per100: 7.5)
        ]
        let change = try #require(ConsumptionEngine.headlineChange(segments: segments, asOf: Self.asOf))
        #expect(change.direction == .improving)
        #expect(abs(change.percent - 20) < 0.01)   // 7.5 -> 6.0
    }

    @Test("a worse current window points the other way")
    func worseCurrentWindowIsWorsening() throws {
        let segments = [
            segment(daysAgo: 10, per100: 8.0), segment(daysAgo: 40, per100: 8.0), segment(daysAgo: 70, per100: 8.0),
            segment(daysAgo: 100, per100: 7.0), segment(daysAgo: 130, per100: 7.0), segment(daysAgo: 160, per100: 7.0)
        ]
        let change = try #require(ConsumptionEngine.headlineChange(segments: segments, asOf: Self.asOf))
        #expect(change.direction == .worsening)
    }

    @Test("a previous window below the floor gives no arrow, even with a rich current window")
    func thinPreviousWindowAbstains() {
        let segments = [
            segment(daysAgo: 10, per100: 6.0), segment(daysAgo: 40, per100: 6.0), segment(daysAgo: 70, per100: 6.0),
            segment(daysAgo: 100, per100: 7.5), segment(daysAgo: 130, per100: 7.5)
        ]
        #expect(ConsumptionEngine.headlineChange(segments: segments, asOf: Self.asOf) == nil)
    }

    @Test("a current window that needs extending is not a window and gives no arrow")
    func extendedCurrentWindowAbstains() {
        let segments = [
            segment(daysAgo: 10, per100: 6.0), segment(daysAgo: 40, per100: 6.0),
            segment(daysAgo: 100, per100: 7.5), segment(daysAgo: 130, per100: 7.5), segment(daysAgo: 160, per100: 7.5)
        ]
        #expect(ConsumptionEngine.headlineChange(segments: segments, asOf: Self.asOf) == nil)
    }

    @Test("a move under the noise threshold gives no arrow")
    func noiseAbstains() {
        let segments = [
            segment(daysAgo: 10, per100: 7.02), segment(daysAgo: 40, per100: 7.02), segment(daysAgo: 70, per100: 7.02),
            segment(daysAgo: 100, per100: 7.0), segment(daysAgo: 130, per100: 7.0), segment(daysAgo: 160, per100: 7.0)
        ]
        #expect(ConsumptionEngine.headlineChange(segments: segments, asOf: Self.asOf) == nil)
    }

    @Test("TrendsStats carries the change beside the headline")
    func trendsStatsExposesTheChange() throws {
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Self.asOf - 400 * Self.day, updatedAt: Self.asOf - 400 * Self.day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 100_000)
        // The `-seedHomeTwoWindows` shape (TrendsTestSeed): eight full tanks
        // 25 days apart, 600 km each - the older three segments at 7.5, the
        // newer four at 6.0.
        var fills: [FillUp] = []
        var odometer = 100_000
        for (index, litres) in [42.0, 45, 45, 45, 36, 36, 36, 36].enumerated() {
            let date = Self.asOf - Double(175 - index * 25) * Self.day
            fills.append(FillUp(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: odometer,
                money: Money(amount: 60, currency: .eur, homeCurrency: .eur),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, volumeL: litres, unitPrice: nil,
                fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
                stationId: nil, crossCheck: .notApplicable, extraction: nil))
            odometer += 600
        }
        let stats = TrendsStats(vehicle: vehicle, entries: fills, asOf: Self.asOf)
        let change = try #require(stats.headlineChange)
        #expect(change.direction == .improving)
        #expect(abs(change.percent - 20) < 0.01)
    }
}
