import Testing
import Foundation
@testable import TankbookCore

/// RV.87: two fill-ups on one day must order by odometer. MFM exports carry a
/// DATE and no time, so two fills on one date land with identical timestamps;
/// `ConsumptionEngine` used to break that tie on `id.uuidString` - creation
/// order, not travel order - so the later fill could sort first, the odometer
/// appear to fall, and both entries get flagged. The odometer is the only
/// ordering fact a dateless entry carries, so the tie now breaks on it, in the
/// ONE order both the engines, the log and the timeline validator read
/// (`EntryOrder`, docs/SCHEMA.md -> Entry -> ordering rule).
///
/// These are L1 tests through the real consumers (engine + validator + log),
/// never an isolated sort assertion: the reported symptom is a fill that is
/// flagged and excluded, so each test asserts the flag is gone and the segment
/// is computed.
@Suite("RV.87 same-day fills order by odometer")
struct SameDayFillOrderingTests {

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil,
            name: "Test car", make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: nil, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, paceLimitKmPerDay: 1500)
    }

    private static var base: Date { Date(timeIntervalSince1970: 1_752_000_000) }

    /// A dateless same-day fill: `createdAt == date` exactly as the MFM import
    /// path writes it (`ImportConversion.makeFill`), so the only remaining
    /// differentiator is whatever the ordering rule decides.
    private static func fill(date: Date, odometer: Int, litres: Double,
                             id: UUID = UUID.v7()) -> FillUp {
        FillUp(
            id: id, createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: nil, note: nil, attachments: [],
            provenance: .import(source: "mfm"), conflict: .none,
            purchaseGroupId: nil, volumeL: litres, unitPrice: nil,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: nil, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    /// Two same-day entries that BOTH record no odometer - an ordinary pair of
    /// expenses on one day. Found by the orchestrator reading the new switch:
    /// `case (nil, _)` also matches `(nil, nil)` and comes first, so the
    /// `(nil, nil)` case the comment relies on was unreachable and both
    /// directions returned true. That is not a strict weak ordering, and
    /// Swift's sort may answer it with an arbitrary order or trap on it.
    ///
    /// The claim is antisymmetry: exactly one of the two directions is true.
    @Test func twoEntriesWithNoOdometerAreOrderedConsistentlyBothWays() {
        let day = Self.base
        let earlier = Self.expense(date: day, createdAt: day)
        let later = Self.expense(date: day, createdAt: day.addingTimeInterval(60))

        #expect(EntryOrder.ascending(earlier, later),
                "the earlier-created entry sorts first when neither records an odometer")
        #expect(!EntryOrder.ascending(later, earlier),
                "and the reverse must be FALSE - both directions true is not an ordering")
    }

    /// An expense with no odometer, which is the ordinary shape: an expense
    /// records money and a date, and often no reading.
    private static func expense(date: Date, createdAt: Date) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: nil, note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            category: .other("parking"), title: "Parking")
    }

    // MARK: - Two fills on one date order by odometer, whatever their ids

    /// The owner's numbers (3 Jun 110 843 and 111 436). The ids are chosen so
    /// uuidString order is the REVERSE of travel order - the higher odometer
    /// has the lexicographically smaller id - proving the ordering follows the
    /// odometer, not the id. Under the old uuid tie-break this pair sorted
    /// wrong, the odometer fell, and both fills were flagged `.order`.
    @Test func twoSameDayFillsOrderByOdometerWhateverTheirIds() {
        let sameDate = Self.base
        let early = Self.fill(date: sameDate, odometer: 110_843, litres: 40,
                              id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!)
        let later = Self.fill(date: sameDate, odometer: 111_436, litres: 30,
                              id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

        // The travel order: 110 843 km first, then 111 436 km.
        let segments = ConsumptionEngine.segments(for: [early, later])
        #expect(segments.count == 1, "the pair must form one segment, not none")
        if let segment = segments.first {
            #expect(segment.openingFillID == early.id)
            #expect(segment.closingFillID == later.id)
            #expect(abs(segment.km - 593) <= 0.005)
            #expect(abs(segment.litres - 30) <= 0.005)
        }

        // The reported symptom: NOTHING is flagged - with the pair correctly
        // ordered, the odometer increases and the timeline check passes.
        let validations = TimelineValidator.validate(entries: [early, later],
                                                     vehicle: Self.vehicle())
        let flags = validations.flatMap(\.flags)
        #expect(flags.isEmpty, "correctly ordered same-day fills must not be flagged")
        #expect(validations.allSatisfy { $0.conflict == .none })
    }

    /// The consumption symptom specifically: under the old id tie-break the
    /// later fill sorted FIRST, so the odometer ran 111436 -> 110843 and the
    /// engine produced no segment between them at all (a segment needs a
    /// strictly increasing odometer). Ordering by odometer makes the segment
    /// appear.
    @Test func correctOrderComputesTheSegmentTheWrongOrderLost() {
        let sameDate = Self.base
        let low = Self.fill(date: sameDate, odometer: 110_843, litres: 40,
                            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!)
        let high = Self.fill(date: sameDate, odometer: 111_436, litres: 30,
                             id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!)

        // Both input orders must give the SAME one segment - recompute is a
        // pure function of the data, never of the array order handed in.
        let forward = ConsumptionEngine.recompute(fills: [low, high])
        let reversed = ConsumptionEngine.recompute(fills: [high, low])
        #expect(forward == reversed)
        #expect(forward.count == 1)
        #expect(forward.first?.closingFillID == high.id)
    }

    // MARK: - Equal odometer on one date (a splash fill)

    /// Two fills, same day, same reading (a top-up / splash fill): no travel
    /// fact separates them, so the ordering falls to creation order
    /// (`createdAt`, then `id`). The point is STABILITY: whatever the input
    /// order, two runs over the same data produce the same result, so a
    /// recompute can never reorder history (docs/SCHEMA.md).
    @Test func equalOdometerSameDayIsDeterministicAcrossTwoRuns() {
        let sameDate = Self.base
        let first = Self.fill(date: sameDate, odometer: 110_843, litres: 20,
                              id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = Self.fill(date: sameDate, odometer: 110_843, litres: 30,
                               id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

        // Run the recompute twice, each time over a different input order:
        // identical output is the deterministic contract.
        let runA = ConsumptionEngine.recompute(fills: [first, second])
        let runB = ConsumptionEngine.recompute(fills: [second, first])
        #expect(runA == runB)

        // Validation is equally deterministic across two runs.
        let validationA = TimelineValidator.validate(entries: [first, second], vehicle: Self.vehicle())
        let validationB = TimelineValidator.validate(entries: [second, first], vehicle: Self.vehicle())
        #expect(validationA == validationB)

        // The decided tie-break, pinned: equal date AND equal odometer order by
        // creation (`createdAt`, then `id`) - the earlier-created fill sorts
        // first, and a recompute can never flip the pair. The ids are chosen so
        // uuid order would say the OPPOSITE (the later-created fill has the
        // smaller uuid) - proving it is creation order that decides.
        let earlier = Self.fill(date: sameDate, odometer: 110_843, litres: 20,
                                id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!)
        var later = Self.fill(date: sameDate, odometer: 110_843, litres: 30,
                              id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        later.createdAt = earlier.createdAt.addingTimeInterval(60)
        #expect(EntryOrder.ascending(earlier, later))
        #expect(!EntryOrder.ascending(later, earlier))
    }

    // MARK: - An entry with a real time still orders by time

    /// The odometer tie-break exists ONLY for identical timestamps. When the
    /// two fills carry real, different times, time still decides - even when
    /// the odometers would say the opposite. A fill at 09:00 with a HIGHER
    /// odometer than a fill at 21:00 is a genuine backwards reading, so the
    /// engine must NOT re-sort it into travel order (that would fabricate an
    /// order the recorded times contradict); the validator must flag the real
    /// regression instead.
    @Test func aRealTimeStillOrdersByTimeNotOdometer() {
        let morning = Self.base.addingTimeInterval(9 * 3600)
        let evening = Self.base.addingTimeInterval(21 * 3600)
        let morningFill = Self.fill(date: morning, odometer: 111_436, litres: 30,
                                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!)
        let eveningFill = Self.fill(date: evening, odometer: 110_843, litres: 40,
                                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!)

        // Time order says morning then evening; that makes the evening fill's
        // odometer fall, which the validator must flag - NOT silently accept
        // by re-sorting the pair into odometer order.
        let validations = TimelineValidator.validate(entries: [morningFill, eveningFill],
                                                     vehicle: Self.vehicle())
        let eveningValidation = validations.first { $0.entryID == eveningFill.id }
        #expect(eveningValidation?.flags.contains { $0.kind == ConflictState.ConflictKind.order } == true,
                "a real odometer regression across a real time gap must still be flagged")

        // And the engine must not close a segment across the falling reading.
        let segments = ConsumptionEngine.segments(for: [morningFill, eveningFill])
        #expect(segments.isEmpty)
    }
}
