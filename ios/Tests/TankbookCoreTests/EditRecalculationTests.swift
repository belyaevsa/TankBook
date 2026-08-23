import Foundation
import Testing
@testable import TankbookCore

// MARK: - P1.6: full-vehicle recompute on edit (docs/SCHEMA.md, Recalculation
// on edit - normative). Every case runs THROUGH the real store (an in-memory
// GRDB repository), not against a hand-built fixture array: the edit is an
// upsert, the recompute reads the store back and feeds
// `ConsumptionEngine.recompute`. The golden expectations come from the
// four-drivers simulation (docs/fixtures/consumption-golden.json, drivers
// D1/D2 and edit cases E1-E3).

// MARK: - Fixtures

private enum UTC {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

/// The golden fixture's fixed "today" - tests are deterministic only because
/// `asOf` is pinned, exactly as the golden corpus does.
private let goldenAsOf = UTC.day(2026, 8, 23)

private func makeRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

private func makeVehicle(vehicleID: UUID, tankCapacityL: Double? = nil) -> Vehicle {
    Vehicle(
        id: vehicleID, createdAt: goldenAsOf, updatedAt: goldenAsOf, deletedAt: nil,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
        plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
        tankCapacityL: tankCapacityL, batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 114_000)
}

/// A fixture fill's data, kept apart from the construction call
/// (the swiftlint function_parameter_count discipline used across the repo).
private struct FillSpec {
    let date: Date
    let odometer: Int
    let litres: Double
    let isFull: Bool
}

private func makeFill(id: UUID = UUID.v7(), vehicleID: UUID, _ spec: FillSpec,
                      money: Money? = nil) -> FillUp {
    FillUp(
        id: id, createdAt: spec.date, updatedAt: spec.date, deletedAt: nil,
        vehicleId: vehicleID, date: spec.date, odometer: spec.odometer,
        money: money, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil,
        volumeL: spec.litres, unitPrice: nil,
        fuelKind: .petrol95, fuelGrade: nil, isFull: spec.isFull,
        tankLevelAfterPct: spec.isFull ? 100 : nil, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

/// The golden D1 series (commuter, full tank every two weeks).
private let d1Specs: [FillSpec] = [
    FillSpec(date: UTC.day(2026, 5, 17), odometer: 114_980, litres: 45.9, isFull: true),
    FillSpec(date: UTC.day(2026, 5, 31), odometer: 115_622, litres: 44.6, isFull: true),
    FillSpec(date: UTC.day(2026, 6, 14), odometer: 116_281, litres: 46.8, isFull: true),
    FillSpec(date: UTC.day(2026, 6, 28), odometer: 116_904, litres: 43.1, isFull: true),
    FillSpec(date: UTC.day(2026, 7, 12), odometer: 117_561, litres: 45.5, isFull: true),
    FillSpec(date: UTC.day(2026, 7, 26), odometer: 118_207, litres: 44.2, isFull: true),
    FillSpec(date: UTC.day(2026, 8, 9), odometer: 118_843, litres: 43.9, isFull: true),
    FillSpec(date: UTC.day(2026, 8, 22), odometer: 119_486, litres: 42.3, isFull: true)
]

/// The golden D2 series (top-up driver - partial fills merge forward into the
/// segment a full fill closes).
private let d2Specs: [FillSpec] = [
    FillSpec(date: UTC.day(2026, 4, 27), odometer: 45_210, litres: 41.0, isFull: true),
    FillSpec(date: UTC.day(2026, 5, 3), odometer: 45_390, litres: 13.5, isFull: false),
    FillSpec(date: UTC.day(2026, 5, 9), odometer: 45_585, litres: 14.0, isFull: false),
    FillSpec(date: UTC.day(2026, 5, 16), odometer: 45_790, litres: 15.0, isFull: false),
    FillSpec(date: UTC.day(2026, 5, 23), odometer: 45_988, litres: 13.0, isFull: false),
    FillSpec(date: UTC.day(2026, 5, 30), odometer: 46_160, litres: 12.5, isFull: false),
    FillSpec(date: UTC.day(2026, 6, 6), odometer: 46_345, litres: 34.5, isFull: true),
    FillSpec(date: UTC.day(2026, 6, 13), odometer: 46_540, litres: 14.5, isFull: false),
    FillSpec(date: UTC.day(2026, 6, 21), odometer: 46_745, litres: 15.0, isFull: false),
    FillSpec(date: UTC.day(2026, 6, 29), odometer: 46_952, litres: 14.0, isFull: false),
    FillSpec(date: UTC.day(2026, 7, 7), odometer: 47_150, litres: 13.5, isFull: false),
    FillSpec(date: UTC.day(2026, 7, 16), odometer: 47_330, litres: 33.0, isFull: true),
    FillSpec(date: UTC.day(2026, 7, 24), odometer: 47_528, litres: 14.0, isFull: false),
    FillSpec(date: UTC.day(2026, 8, 2), odometer: 47_739, litres: 15.5, isFull: false),
    FillSpec(date: UTC.day(2026, 8, 11), odometer: 47_945, litres: 14.5, isFull: false),
    FillSpec(date: UTC.day(2026, 8, 21), odometer: 48_140, litres: 32.5, isFull: true)
]

private func d1Fills(vehicleID: UUID) -> [FillUp] {
    d1Specs.map { makeFill(vehicleID: vehicleID, $0) }
}

private func d2Fills(vehicleID: UUID) -> [FillUp] {
    d2Specs.map { makeFill(vehicleID: vehicleID, $0) }
}

// MARK: - Store helpers (the "through the real store" contract)

private func seed(_ repository: TankbookRepository, vehicle: Vehicle,
                  fills: [FillUp]) throws {
    try repository.upsertVehicle(vehicle)
    for fill in fills {
        try repository.upsertFillUp(fill)
    }
}

/// Reads the store and runs the full recompute - the exact call the edit save
/// path makes (docs/SCHEMA.md, Recalculation on edit).
private func recomputeHeadline(_ repository: TankbookRepository, vehicle: Vehicle,
                               asOf: Date = goldenAsOf) throws -> Headline? {
    let fills = try repository.liveFillUps(forVehicle: vehicle.id)
    let segments = ConsumptionEngine.recompute(fills: fills, tankCapacityL: vehicle.tankCapacityL)
    return ConsumptionEngine.headline(segments: segments, asOf: asOf)
}

private func recomputeSegments(_ repository: TankbookRepository, vehicle: Vehicle) throws -> [Segment] {
    let fills = try repository.liveFillUps(forVehicle: vehicle.id)
    return ConsumptionEngine.recompute(fills: fills, tankCapacityL: vehicle.tankCapacityL)
}

private func updateFill(_ repository: TankbookRepository, vehicleID: UUID, id: UUID,
                        _ mutate: (inout FillUp) -> Void) throws {
    var fills = try repository.liveFillUps(forVehicle: vehicleID)
    guard let index = fills.firstIndex(where: { $0.id == id }) else {
        Issue.record("edit target fill \(id) not found")
        return
    }
    mutate(&fills[index])
    try repository.upsertFillUp(fills[index])
}

private func round2(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

// MARK: - Volume edit shifts the headline (golden E1)

@Test func volumeEditShiftsHeadlineToDocumentedValue() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d1Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    let before = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(before) == 6.9)

    // Golden E1: the 2026-07-12 fill's volume 45.5 -> 40.5.
    let target = fills.first { $0.date == UTC.day(2026, 7, 12) }!.id
    try updateFill(repository, vehicleID: vehicleID, id: target) { $0.volumeL = 40.5 }

    let after = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(after) == 6.8)
    #expect(ConsumptionDelta.hasChanged(before: before, after: after))

    // The segment the edit closed: 40.5 / 657 km x 100 = 6.16 (golden E1).
    let segments = try recomputeSegments(repository, vehicle: vehicle)
    let editedSegment = segments.first { $0.closes == UTC.day(2026, 7, 12) }
    #expect(round2(editedSegment?.per100 ?? -1) == 6.16)
}

// MARK: - isFull toggle splits / merges (golden E2, E3)

@Test func isFullToggleOffMergesTwoSegmentsIntoOne() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d1Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    // Golden E2: toggle 2026-06-28 (a full fill) to partial -> two segments
    // merge into one closing at 07-12, and the count drops 7 -> 6.
    let target = fills.first { $0.date == UTC.day(2026, 6, 28) }!.id
    try updateFill(repository, vehicleID: vehicleID, id: target) { $0.isFull = false; $0.tankLevelAfterPct = nil }

    let segments = try recomputeSegments(repository, vehicle: vehicle)
    #expect(segments.count == 6)
    let merged = segments.first { $0.closes == UTC.day(2026, 7, 12) }
    #expect(abs((merged?.km ?? -1) - 1_280) <= 0.005)
    #expect(abs((merged?.litres ?? -1) - 88.6) <= 0.005)
    #expect(round2(merged?.per100 ?? -1) == 6.92)
}

@Test func isFullToggleOnSplitsOneSegmentIntoTwo() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d2Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    // Golden E3: toggle the 2026-05-16 partial to full -> one segment splits
    // into two: one closing at 05-16, one closing at 06-06.
    let target = fills.first { $0.date == UTC.day(2026, 5, 16) }!.id
    try updateFill(repository, vehicleID: vehicleID, id: target) { $0.isFull = true; $0.tankLevelAfterPct = 100 }

    let segments = try recomputeSegments(repository, vehicle: vehicle)
    #expect(segments.count == 4)

    let splitA = segments.first { $0.closes == UTC.day(2026, 5, 16) }
    #expect(abs((splitA?.km ?? -1) - 580) <= 0.005)
    #expect(abs((splitA?.litres ?? -1) - 42.5) <= 0.005)
    #expect(round2(splitA?.per100 ?? -1) == 7.33)

    let splitB = segments.first { $0.closes == UTC.day(2026, 6, 6) }
    #expect(abs((splitB?.km ?? -1) - 555) <= 0.005)
    #expect(abs((splitB?.litres ?? -1) - 60.0) <= 0.005)
    #expect(round2(splitB?.per100 ?? -1) == 10.81)
}

// MARK: - Date edit re-orders a fill into another segment

@Test func dateEditMovesFillIntoAnotherSegmentAndChangesBoth() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d2Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    let segmentsBefore = try recomputeSegments(repository, vehicle: vehicle)
    let s1Before = segmentsBefore.first { $0.closes == UTC.day(2026, 6, 6) }!
    let s2Before = segmentsBefore.first { $0.closes == UTC.day(2026, 7, 16) }!
    #expect(abs(s1Before.litres - 102.5) <= 0.005)   // the golden D2 values
    #expect(abs(s2Before.litres - 90.0) <= 0.005)

    // Move the 2026-05-30 partial fill (12.5 L) across the 06-06 full boundary:
    // its litres leave the 06-06 segment and join the 07-16 segment. Both
    // affected segments must change - this is why a recompute is full.
    let target = fills.first { $0.date == UTC.day(2026, 5, 30) }!.id
    try updateFill(repository, vehicleID: vehicleID, id: target) {
        $0.date = UTC.day(2026, 6, 10)
    }

    let segmentsAfter = try recomputeSegments(repository, vehicle: vehicle)
    let s1After = segmentsAfter.first { $0.closes == UTC.day(2026, 6, 6) }
    let s2After = segmentsAfter.first { $0.closes == UTC.day(2026, 7, 16) }
    #expect(abs((s1After?.litres ?? -1) - 90.0) <= 0.005)    // lost 12.5 L
    #expect(abs((s2After?.litres ?? -1) - 102.5) <= 0.005)   // gained 12.5 L
    #expect(s1After?.km == s1Before.km)                      // km unchanged
    #expect(s2After?.km == s2Before.km)
}

// MARK: - Odometer edit changes two segments (a full fill is a boundary)

@Test func odometerEditChangesTwoSegments() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d1Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    let segmentsBefore = try recomputeSegments(repository, vehicle: vehicle)
    let closingBefore = segmentsBefore.first { $0.closes == UTC.day(2026, 6, 14) }!
    let openingBefore = segmentsBefore.first { $0.closes == UTC.day(2026, 6, 28) }!
    #expect(abs(closingBefore.km - 659) <= 0.005)
    #expect(abs(openingBefore.km - 623) <= 0.005)

    // Move the 06-14 full fill's odometer: it is BOTH the close of the segment
    // before it and the open of the segment after it, so both change.
    let target = fills.first { $0.date == UTC.day(2026, 6, 14) }!.id
    try updateFill(repository, vehicleID: vehicleID, id: target) { $0.odometer = 116_800 }

    let segmentsAfter = try recomputeSegments(repository, vehicle: vehicle)
    let closingAfter = segmentsAfter.first { $0.closes == UTC.day(2026, 6, 14) }
    let openingAfter = segmentsAfter.first { $0.closes == UTC.day(2026, 6, 28) }
    #expect(abs((closingAfter?.km ?? -1) - 1_178) <= 0.005)   // 116800 - 115622
    #expect(abs((openingAfter?.km ?? -1) - 104) <= 0.005)     // 116904 - 116800
}

// MARK: - Delete then restore returns exact prior stats

@Test func deleteThenRestoreReturnsExactPriorStats() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d1Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    let beforeSegments = try recomputeSegments(repository, vehicle: vehicle)
    let beforeHeadline = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(beforeHeadline) == 6.9)

    // Delete the 07-12 fill (tombstone, 30-day window - P1.7 renders it).
    let target = fills.first { $0.date == UTC.day(2026, 7, 12) }!.id
    try repository.softDeleteFillUp(id: target)
    let afterDeleteHeadline = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(afterDeleteHeadline) != 6.9)

    // Restore: the stats come back EXACTLY - nothing lost silently (hard rule 8).
    try repository.restoreFillUp(id: target)
    let afterRestoreSegments = try recomputeSegments(repository, vehicle: vehicle)
    let afterRestoreHeadline = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(afterRestoreSegments == beforeSegments)
    #expect(ConsumptionDelta.displayedValue(afterRestoreHeadline) == 6.9)
    #expect(!ConsumptionDelta.hasChanged(before: beforeHeadline, after: afterRestoreHeadline))
}

// MARK: - No-op edit produces no delta (the toast-suppression case)

@Test func noOpEditProducesNoDelta() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d1Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    let before = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(before) == 6.9)

    // Re-upsert an unchanged fill: the recompute result must be identical, so
    // the UI shows no delta toast (docs/ERRORS.md -> Edit entry, row 4).
    let unchanged = fills[4]
    try repository.upsertFillUp(unchanged)
    let after = try recomputeHeadline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(after) == 6.9)
    #expect(!ConsumptionDelta.hasChanged(before: before, after: after))
}

// MARK: - Editing an amount clears the rate snapshot (hard rule 3)

@Test func editingAmountClearsRateSnapshotAndKeepsRateDateAtEntryDate() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    try repository.upsertVehicle(vehicle)

    // A PLN fill with a completed snapshot as of the entry date.
    let entryDate = UTC.day(2026, 5, 31)
    let snapshot = RateSnapshot(rate: Decimal(string: "4.2706")!,
                                rateDate: entryDate, source: .ecb)
    let money = Money(amount: Decimal(string: "289.50")!, currency: .pln,
                      homeCurrency: .eur)
        .converted(using: snapshot)
    #expect(money.hasSnapshot)
    #expect(money.rateDate == entryDate)
    #expect(money.homeAmount == Decimal(string: "67.79")!)   // 289.50 / 4.2706

    let fill = makeFill(vehicleID: vehicleID,
                        FillSpec(date: entryDate, odometer: 115_622, litres: 42.3, isFull: true),
                        money: money)
    try repository.upsertFillUp(fill)

    // The edit path edits the amount through the Money pair (hard rule 3):
    // the snapshot clears for re-conversion, `rateDate` stays the entry date.
    let stored = try repository.liveFillUps(forVehicle: vehicleID).first!
    let edited = stored.money!.replacingAmount(Decimal(string: "300.00")!)
    #expect(!edited.hasSnapshot)
    #expect(edited.rate == nil)
    #expect(edited.rateDate == nil)
    #expect(edited.currency == .pln)

    var editedFill = stored
    editedFill.money = edited
    try repository.upsertFillUp(editedFill)

    let readBack = try repository.liveFillUps(forVehicle: vehicleID).first!
    #expect(readBack.money?.hasSnapshot == false)

    // When the rate arrives later, the backfill snapshot carries the ENTRY date
    // (never today), exactly the money rules the existing L1 suite enforces.
    let reConverted = readBack.money!.converted(using: snapshot)
    #expect(reConverted.rateDate == entryDate)
    #expect(reConverted.rate == Decimal(string: "4.2706")!)
}

// MARK: - Recompute is full, not surgical

@Test func recomputeIsFullAnEditToOldestFillChangesASegmentFarFromIt() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    let fills = d2Fills(vehicleID: vehicleID)
    try seed(repository, vehicle: vehicle, fills: fills)

    let before = try recomputeSegments(repository, vehicle: vehicle)
    #expect(before.count == 3)
    let farBefore = before.first { $0.closes == UTC.day(2026, 7, 16) }!
    #expect(abs(farBefore.km - 985) <= 0.005)
    #expect(abs(farBefore.litres - 90.0) <= 0.005)

    // Move the OLDEST fill (2026-04-27, the first segment's opening boundary)
    // deep into the middle of the history. Its removal re-bases every boundary
    // after it: the 07-16 segment - three segments away - must change, and the
    // final 08-21 segment must still recompute to its exact prior value.
    let oldest = fills.first { $0.date == UTC.day(2026, 4, 27) }!.id
    try updateFill(repository, vehicleID: vehicleID, id: oldest) {
        $0.date = UTC.day(2026, 6, 20)
    }

    let after = try recomputeSegments(repository, vehicle: vehicle)
    let farAfter = after.first { $0.closes == UTC.day(2026, 7, 16) }
    #expect(farAfter != nil)
    #expect(abs((farAfter?.km ?? -1) - 2_120) <= 0.005)     // was 985
    #expect(abs((farAfter?.litres ?? -1) - 75.5) <= 0.005)  // was 90.0

    // The untouched tail segment recomputes to its golden value - the full pass
    // covered it too and did not corrupt it.
    let tailAfter = after.first { $0.closes == UTC.day(2026, 8, 21) }
    #expect(abs((tailAfter?.km ?? -1) - 810) <= 0.005)
    #expect(abs((tailAfter?.litres ?? -1) - 76.5) <= 0.005)
}
