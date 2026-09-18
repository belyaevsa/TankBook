import Testing
import Foundation
@testable import TankbookCore

/// The after-save one-liner (docs/JOURNEYS.md J3 → Done). The property under
/// test: every message is read off the engine's figures for the SAVED fill,
/// and a save the data cannot yet describe yields `nil` - never a number the
/// engine did not produce.
struct AfterSaveInsightTests {

    // 2025-07-06, so "this year" is 2025.
    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: asOf - 400 * day, updatedAt: asOf - 400 * day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(daysAgo: Double, odometer: Int, litres: Double, isFull: Bool) -> FillUp {
        let date = asOf - daysAgo * day
        return FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Money(amount: 50, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: litres, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: isFull,
            tankLevelAfterPct: isFull ? 100 : nil, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    private static func stats(_ fills: [FillUp]) -> HomeStats {
        HomeStats(vehicle: vehicle(), entries: fills, asOf: asOf)
    }

    @Test("a full tank that closes a segment reports that segment's figure")
    func closingFillReportsItsSegment() throws {
        let opening = Self.fill(daysAgo: 20, odometer: 120_000, litres: 40, isFull: true)
        let saved = Self.fill(daysAgo: 10, odometer: 120_500, litres: 34, isFull: true)
        let insight = AfterSaveInsight.derive(saved: saved, stats: Self.stats([opening, saved]))
        let expected = try #require(insight)
        guard case .segmentClosed(let per100, let isBest) = expected else {
            Issue.record("expected a closed segment, got \(expected)")
            return
        }
        #expect(abs(per100 - 6.8) < 0.001)   // 34 L over 500 km
        #expect(isBest)                      // the only segment of the year
    }

    @Test("a worse fill than an earlier one this year is not the best")
    func worseSegmentIsNotBest() throws {
        let first = Self.fill(daysAgo: 60, odometer: 120_000, litres: 40, isFull: true)
        let second = Self.fill(daysAgo: 40, odometer: 120_500, litres: 30, isFull: true)   // 6.0
        let saved = Self.fill(daysAgo: 10, odometer: 121_000, litres: 36, isFull: true)    // 7.2
        let insight = AfterSaveInsight.derive(saved: saved, stats: Self.stats([first, second, saved]))
        guard case .segmentClosed(let per100, let isBest)? = insight else {
            Issue.record("expected a closed segment")
            return
        }
        #expect(abs(per100 - 7.2) < 0.001)
        #expect(!isBest)
    }

    @Test("best is judged at the displayed precision, so a tie reads as best")
    func bestIsJudgedAtDisplayPrecision() throws {
        let first = Self.fill(daysAgo: 60, odometer: 120_000, litres: 40, isFull: true)
        let second = Self.fill(daysAgo: 40, odometer: 120_500, litres: 33.9, isFull: true)  // 6.78 -> 6.8
        let saved = Self.fill(daysAgo: 10, odometer: 121_000, litres: 34.1, isFull: true)   // 6.82 -> 6.8
        let insight = AfterSaveInsight.derive(saved: saved, stats: Self.stats([first, second, saved]))
        guard case .segmentClosed(_, let isBest)? = insight else {
            Issue.record("expected a closed segment")
            return
        }
        #expect(isBest)
    }

    @Test("the first full tank closes nothing and names the next step")
    func firstFullTankNamesTheNextStep() {
        let saved = Self.fill(daysAgo: 1, odometer: 120_000, litres: 40, isFull: true)
        #expect(AfterSaveInsight.derive(saved: saved, stats: Self.stats([saved])) == .needsAnotherFullTank)
    }

    @Test("a partial fill with nothing to say says nothing")
    func partialFillWithNoSegmentIsSilent() {
        let saved = Self.fill(daysAgo: 1, odometer: 120_000, litres: 20, isFull: false)
        #expect(AfterSaveInsight.derive(saved: saved, stats: Self.stats([saved])) == nil)
    }

    @Test("a fill that is not the one closing the latest segment reports nothing fabricated")
    func nonClosingFillIsSilent() {
        // Two full tanks close a segment; the SAVED fill is a partial after
        // them, which opens nothing and closes nothing.
        let first = Self.fill(daysAgo: 30, odometer: 120_000, litres: 40, isFull: true)
        let second = Self.fill(daysAgo: 20, odometer: 120_500, litres: 34, isFull: true)
        let saved = Self.fill(daysAgo: 1, odometer: 120_800, litres: 15, isFull: false)
        #expect(AfterSaveInsight.derive(saved: saved, stats: Self.stats([first, second, saved])) == nil)
    }
}
