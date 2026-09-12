import Testing
import Foundation
@testable import TankbookCore

// RV.229 - the import review must not label a CHECK 5 consumption outlier
// "Breaks the timeline". The odometer and date are internally consistent, so
// the fields to question are the litres and the odometer: a different kind,
// label and next step from a timeline break (hard rule 7).

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

private func vehicle() -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
        powertrain: .ice, fuelKinds: [.diesel], tankCapacityL: 71,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                             energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 100_000)
}

private func existingFill(date: Date, odometer: Int, volumeL: Double) -> FillUp {
    FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: UUID.v7(), date: date, odometer: odometer,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil, volumeL: volumeL, unitPrice: nil,
        fuelKind: .diesel, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
        stationId: nil, crossCheck: .notApplicable, extraction: nil)
}

/// The incoming outlier: 8 L at 1.85/L over the 500 km since the prior full
/// fill = 1.6 L/100km, below the ICE band. The money reconciles with the litres,
/// so the row's only possible flag is the CHECK 5 outlier.
private func outlierCandidate(date: Date, odometer: Int, sourceRow: Int) -> ImportCandidate {
    ImportCandidate(
        entityType: "fillUp", date: date, odometer: odometer, volumeL: 8,
        unitPrice: "1.85", money: ImportMoney(amount: "14.80", currency: "USD"),
        fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: nil,
        vehicleName: "Volvo",
        provenance: ImportProvenance(tag: "import", source: "mfm"),
        sourceRow: sourceRow)
}

@Suite("RV.229 import consumption label")
struct RV229ImportConsumptionLabelTests {

    @Test func aConsumptionOnlyFlagClassifiesToTheConsumptionKind() {
        let car = vehicle()
        let prior = existingFill(date: epoch, odometer: 100_000, volumeL: 42.3)
        let outlier = outlierCandidate(date: epoch + 5 * day, odometer: 100_500, sourceRow: 2)

        let (ready, review) = ImportReviewClassifier.partition(
            candidates: [outlier], unparsed: [], rawLinesByRow: [:],
            vehicle: car, source: "mfm", existingEntries: [prior])

        guard let row = review.first(where: { $0.sourceRow == 2 }) else {
            Issue.record("the outlier must land in the review list, ready=\(ready.count)")
            return
        }
        guard case .consumptionOutlier(let per100, let range) = row.kind else {
            Issue.record("a consumption-only flag must classify to .consumptionOutlier, got \(row.kind)")
            return
        }
        // The figure is the engine's own segment figure, and it is outside the
        // car's band - the same value and band the flag carries.
        #expect(abs(per100 - 1.6) < 1e-9, "8 L over 500 km is 1.6 L/100km, got \(per100)")
        #expect(!range.contains(per100), "the flagged figure must be outside the band")
        var isTimeline = false
        if case .timelineConflict = row.kind { isTimeline = true }
        #expect(!isTimeline, "a consumption-only flag must never wear the timeline kind")
    }

    @Test func aRowWithBothFlagsKeepsTheTimelineKind() {
        let car = vehicle()
        // The outlier also breaks the order: the next entry sits BELOW it, so
        // the row carries both an `.order` and a `.consumption` flag. The
        // timeline is the harder error and keeps its own kind and next step.
        let prior = existingFill(date: epoch, odometer: 100_000, volumeL: 42.3)
        let after = existingFill(date: epoch + 10 * day, odometer: 100_200, volumeL: 40)
        let outlier = outlierCandidate(date: epoch + 5 * day, odometer: 100_500, sourceRow: 2)

        let (_, review) = ImportReviewClassifier.partition(
            candidates: [outlier], unparsed: [], rawLinesByRow: [:],
            vehicle: car, source: "mfm", existingEntries: [prior, after])

        guard let row = review.first(where: { $0.sourceRow == 2 }) else {
            Issue.record("the row must land in the review list")
            return
        }
        guard case .timelineConflict(let kind) = row.kind else {
            Issue.record("a row with both flags must keep .timelineConflict, got \(row.kind)")
            return
        }
        #expect(kind == .order, "the timeline flag is the harder error")
    }
}
