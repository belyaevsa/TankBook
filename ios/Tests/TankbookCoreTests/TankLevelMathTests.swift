import Testing
import Foundation
@testable import TankbookCore

// MARK: - TANK-LEVEL refinement (docs/SCHEMA.md, Derived: consumption)

// litres_adjusted = Σ volume + (levelOpen − levelClose)/100 × capacity, gated
// on tankCapacityL being set; falls back to full-to-full otherwise. The D1–D4
// golden vectors must not move (they call the engine without a capacity).

private func tankFill(id: UUID = UUID.v7(), date: Date, odometer: Int, litres: Double,
                      isFull: Bool, level: Double? = nil) -> FillUp {
    FillUp(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: UUID.v7(), date: date, odometer: odometer,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil,
        volumeL: litres, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
        isFull: isFull, tankLevelAfterPct: level, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

@Test func tankLevelFormulaAdjustsByLevelDelta() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var open = tankFill(date: base, odometer: 100_000, litres: 40, isFull: true, level: 100)
    var close = tankFill(date: base + 10 * day, odometer: 100_400, litres: 30,
                         isFull: false, level: 50)

    let segments = ConsumptionEngine.segments(for: [open, close], tankCapacityL: 60)
    // Worked by hand: 30 + (100 − 50)/100 × 60 = 30 + 30 = 60; km = 400.
    #expect(segments.count == 1)
    #expect(abs((segments.first?.litres ?? 0) - 60) < 0.0001)
    #expect(abs((segments.first?.km ?? 0) - 400) < 0.0001)
    #expect(abs((segments.first?.per100 ?? 0) - 15) < 0.0001)
}

@Test func tankLevelSignClosingFullerYieldsSmallerAdjustedLitres() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var open = tankFill(date: base, odometer: 100_000, litres: 40, isFull: false, level: 40)
    var close = tankFill(date: base + 10 * day, odometer: 100_400, litres: 30,
                         isFull: false, level: 60)

    let segments = ConsumptionEngine.segments(for: [open, close], tankCapacityL: 60)
    // Closing fuller than it opened: the car burned LESS than what was poured,
    // so the adjusted litres must be SMALLER than the poured volume, and the
    // sign of the delta must match (levelOpen − levelClose), in that order.
    let litres = segments.first?.litres ?? 0
    #expect(segments.count == 1)
    #expect(litres < 30, "closing fuller must reduce adjusted litres below poured")
    #expect(abs(litres - 18) < 0.0001)   // 30 + (40 − 60)/100 × 60 = 30 − 12
}

@Test func tankLevelHundredPercentPartialMatchesFullToFull() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    // History A: the closing fill is a full fill.
    let aOpen = tankFill(date: base, odometer: 100_000, litres: 40, isFull: true, level: 100)
    let aClose = tankFill(date: base + 10 * day, odometer: 100_400, litres: 30, isFull: true, level: 100)
    // History B: the SAME history, the closing fill expressed as a partial at 100%.
    var bOpen = tankFill(date: base, odometer: 100_000, litres: 40, isFull: true, level: 100)
    var bClose = tankFill(date: base + 10 * day, odometer: 100_400, litres: 30,
                          isFull: false, level: 100)

    let aSegments = ConsumptionEngine.segments(for: [aOpen, aClose], tankCapacityL: 60)
    let bSegments = ConsumptionEngine.segments(for: [bOpen, bClose], tankCapacityL: 60)
    #expect(aSegments.count == 1)
    #expect(bSegments.count == 1)
    #expect(abs((aSegments.first?.litres ?? 0) - (bSegments.first?.litres ?? 0)) < 0.0001)
    #expect(abs((aSegments.first?.km ?? 0) - (bSegments.first?.km ?? 0)) < 0.0001)

    // And the headline is identical: 100% means the same thing as a full fill.
    let asOf = base + 20 * day
    let aHeadline = ConsumptionEngine.headline(segments: aSegments, asOf: asOf, windowDays: 90, floor: 3)
    let bHeadline = ConsumptionEngine.headline(segments: bSegments, asOf: asOf, windowDays: 90, floor: 3)
    #expect(aHeadline != nil)
    #expect(bHeadline != nil)
    #expect(abs((aHeadline?.value ?? 0) - (bHeadline?.value ?? 0)) < 0.0001)
    #expect(abs((aHeadline?.totalLitres ?? 0) - (bHeadline?.totalLitres ?? 0)) < 0.0001)
}

@Test func tankLevelNoCapacityFallsBackToFullToFull() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var open = tankFill(date: base, odometer: 100_000, litres: 40, isFull: true, level: 100)
    var partial = tankFill(date: base + 10 * day, odometer: 100_400, litres: 15,
                           isFull: false, level: 60)
    var close = tankFill(date: base + 20 * day, odometer: 100_800, litres: 42, isFull: true, level: 100)

    // Without a capacity there is no litres equivalence and NO adjustment: the
    // partial fill does not close a segment, and the fallback is the plain
    // full-to-full sum (15 + 42), not a crash and not a guessed number.
    let segments = ConsumptionEngine.segments(for: [open, partial, close], tankCapacityL: nil)
    #expect(segments.count == 1)
    #expect(segments.first?.closingFillID == close.id,
            "the segment must close at the next full fill, not the partial")
    #expect(abs((segments.first?.litres ?? 0) - 57) < 0.0001)
    #expect(abs((segments.first?.km ?? 0) - 800) < 0.0001)
}

@Test func tankLevelUnsetLevelIsOptInPerEntry() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var open = tankFill(date: base, odometer: 100_000, litres: 40, isFull: true, level: 100)
    // A partial fill WITHOUT a level: even with a capacity set it is not a
    // boundary - the refinement is opt-in per entry, so this behaves exactly as
    // before the feature existed.
    var partial = tankFill(date: base + 10 * day, odometer: 100_400, litres: 15,
                           isFull: false, level: nil)
    var close = tankFill(date: base + 20 * day, odometer: 100_800, litres: 42, isFull: true, level: 100)

    let segments = ConsumptionEngine.segments(for: [open, partial, close], tankCapacityL: 60)
    #expect(segments.count == 1)
    #expect(segments.first?.closingFillID == close.id)
    #expect(abs((segments.first?.litres ?? 0) - 57) < 0.0001)
}

@Test func tankLevelConflictFlaggedEntryStaysExcluded() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var open = tankFill(date: base, odometer: 100_000, litres: 40, isFull: true, level: 100)
    var flagged = tankFill(date: base + 10 * day, odometer: 100_400, litres: 20,
                           isFull: false, level: 60)
    flagged.conflict = .flagged(kind: .order, detectedAt: base)
    var close = tankFill(date: base + 20 * day, odometer: 100_800, litres: 42, isFull: true, level: 100)

    // A conflict-flagged entry is excluded from consumption math even when tank
    // level makes it a boundary: no segment may touch it.
    let segments = ConsumptionEngine.segments(for: [open, flagged, close], tankCapacityL: 60)
    #expect(segments.isEmpty)
}
