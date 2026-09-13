import Testing
import Foundation
@testable import TankbookCore

// RV.276: two fill-ups at one reading on one day are ONE STOP, not a conflict.
// Equality between two travel entries is a conflict only when their DATES
// differ; a same-day pair is a split payment or two products at one till
// (receipt-062/063), and the old strict rule told the user to change an
// odometer that is right (docs/SCHEMA.md, Validation).
//
// L1 through the real consumers: the validator (flags + suggestions) and the
// consumption engine (segment volumes). The vacuous trap - allowing equality on
// different days too - has its own test below.

private let rv276Epoch = Date(timeIntervalSince1970: 1_752_000_000)
private let rv276Minute: TimeInterval = 60
private let rv276Day: TimeInterval = 86_400

private func rv276Vehicle(paceLimit: Double = 1500) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: rv276Epoch, updatedAt: rv276Epoch, deletedAt: nil,
        name: "Same-stop car", make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                             energy: .kWhPer100),
        photo: nil, paceLimitKmPerDay: paceLimit)
}

private func rv276Fill(date: Date, odometer: Int?, litres: Double = 40,
                       id: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil, vehicleId: UUID.v7(),
        date: date, odometer: odometer, money: nil, note: nil, attachments: [],
        provenance: .manual, conflict: .none, purchaseGroupId: nil, volumeL: litres,
        unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil, isFull: true,
        tankLevelAfterPct: nil, stationId: nil, crossCheck: .notApplicable, extraction: nil)
}

@Suite("RV.276 two fill-ups at one reading on one day")
struct RV276SameStopPairTests {

    /// The defect: two fills at one reading two minutes apart on one day. Before
    /// the fix both were order-flagged AND carried a suggestion to move an
    /// odometer that is correct.
    @Test func sameDaySameReadingIsOneStopNotAConflict() {
        let first = rv276Fill(date: rv276Epoch, odometer: 401_544)
        let second = rv276Fill(date: rv276Epoch + 2 * rv276Minute, odometer: 401_544)

        let validations = TimelineValidator.validate(entries: [first, second], vehicle: rv276Vehicle())
        for validation in validations {
            #expect(validation.flags.isEmpty, "a same-day same-reading pair must not flag")
            #expect(validation.conflict == .none, "and it must not carry a conflict state")
            #expect(validation.suggestions.isEmpty, "and it must offer no resolution")
        }
        #expect(TimelineValidator.invariantHolds(entries: [first, second]),
                "the invariant holds for one stop written twice")
    }

    /// The vacuous trap: equality on DIFFERENT days is still a claim of travel
    /// that did not happen, so it stays order-flagged.
    @Test func differentDaysSameReadingStillFlag() {
        let first = rv276Fill(date: rv276Epoch, odometer: 401_544)
        let second = rv276Fill(date: rv276Epoch + rv276Day, odometer: 401_544)

        let validations = TimelineValidator.validate(entries: [first, second], vehicle: rv276Vehicle())
        for validation in validations {
            #expect(validation.flags.contains { $0.kind == .order },
                    "a different-day equal reading must stay flagged")
        }
        #expect(!TimelineValidator.invariantHolds(entries: [first, second]),
                "the invariant breaks for equal readings on different days")
    }

    /// The valid range follows the rule: a same-day same-reading neighbour makes
    /// the order bound inclusive (the old window's lower end was previous + 1).
    @Test func sameDayNeighbourMakesTheOdometerBoundInclusive() {
        let first = rv276Fill(date: rv276Epoch, odometer: 401_544)
        let second = rv276Fill(date: rv276Epoch + 2 * rv276Minute, odometer: 401_544)

        let range = TimelineValidator.validate(entries: [first, second], vehicle: rv276Vehicle())
            .first { $0.entryID == second.id }?.validRange
        if case .bounded(let lower, _) = range?.odometer {
            #expect(lower == 401_544, "the same-day bound is inclusive, got \(String(describing: lower))")
        } else {
            #expect(Bool(false), "the odometer range must be bounded")
        }
        if case .bounded = range?.dates {} else {
            #expect(Bool(false), "the equal same-day reading has a valid date (its neighbour's day)")
        }
    }

    /// Consumption: the zero-km pair is one stop, so it produces no segment and
    /// no volume is dropped. Over the whole history the figure equals the merged
    /// single fill's - and no zero-km segment appears.
    @Test func zeroDistancePairMatchesTheMergedSingleFill() {
        let stop = rv276Epoch
        let first = rv276Fill(date: stop, odometer: 100_000, litres: 20)
        let second = rv276Fill(date: stop + 2 * rv276Minute, odometer: 100_000, litres: 30)
        let next = rv276Fill(date: stop + 10 * rv276Day, odometer: 100_400, litres: 40)

        let pairSegments = ConsumptionEngine.segments(for: [first, second, next])
        #expect(pairSegments.allSatisfy { $0.km > 0 },
                "a same-reading pair must never close a zero-km segment")
        #expect(pairSegments.count == 1, "the pair and the next fill form one segment")

        let merged = rv276Fill(date: stop, odometer: 100_000, litres: 50)
        let mergedSegments = ConsumptionEngine.segments(for: [merged, next])

        #expect(ConsumptionEngine.lifetime(segments: pairSegments)
            == ConsumptionEngine.lifetime(segments: mergedSegments),
            "the folded pair's consumption equals the merged single fill's")
    }
}
