import Testing
import Foundation
@testable import TankbookCore

// RV.341: CHECK 2 judges a car by how it is driven. Two fills on different
// calendar days count at least one day apart, the limit is learned from the
// car's own readings once it has `paceLearningReadings` of them, and a limit
// the user set applies as set (docs/SCHEMA.md, Validation -> CHECK 2).

/// UTC so "same day" never depends on the machine's timezone.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2025-07-14 00:00:00 UTC.
private let base = Date(timeIntervalSince1970: 1_752_451_200)
private let day: TimeInterval = 86_400

private func at(_ dayOffset: Int, _ hour: Int) -> Date {
    base + Double(dayOffset) * day + Double(hour) * 3_600
}

private func vehicle(paceLimit: Double = TimelineValidator.defaultPaceLimitKmPerDay) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil,
        name: "Test car", make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l,
                             consumption: .lPer100, energy: .kWhPer100),
        photo: nil, paceLimitKmPerDay: paceLimit
    )
}

private func fill(_ date: Date, _ odometer: Int, id: UUID = UUID.v7()) -> FillUp {
    FillUp(id: id, createdAt: date, updatedAt: date, vehicleId: UUID.v7(), date: date,
           odometer: odometer, provenance: .manual, volumeL: 40, fuelKind: .petrol95,
           isFull: true, crossCheck: .notApplicable)
}

/// `count` fills, one a day at noon from day 0, `kmPerDay` apart, ending at
/// `count - 1`; returns them and the last reading.
private func history(count: Int, kmPerDay: Int, from odometer: Int = 50_000) -> ([any Entry], Int) {
    let fills = (0..<count).map { fill(at($0, 12), odometer + $0 * kmPerDay) }
    return (fills, odometer + (count - 1) * kmPerDay)
}

private func paceFlags(_ entries: [any Entry], _ id: UUID, vehicle: Vehicle = vehicle(),
                       pace: TimelineValidator.PacePolicy = .learned) -> [TimelineValidator.Flag] {
    (TimelineValidator.validate(entries: entries, vehicle: vehicle, calendar: calendar, pace: pace)
        .first { $0.entryID == id }?.flags ?? [])
        .filter { $0.kind == .pace }
}

@Suite("RV.341 pace learned from the car")
struct RV341PaceLearningTests {

    /// The owner's report: 62 867 km late on 22 Oct, 63 163 km three hours
    /// later on 23 Oct - 296 km of motorway. Divided by three hours that is
    /// 2 368 km/day; counted as one day it is 296.
    @Test func aMotorwayLegAcrossMidnightIsNotFlagged() {
        let (past, last) = history(count: 12, kmPerDay: 350)
        let entryID = UUID.v7()
        let entries = past + [
            fill(at(12, 22), last + 350),
            fill(at(13, 1), last + 646, id: entryID),
            fill(at(13, 20), last + 1_048)
        ]
        #expect(paceFlags(entries, entryID).isEmpty)
    }

    /// A misread digit is still caught once the car has a history: 3 500 km in
    /// a day for a car that does 350.
    @Test func aMisreadReadingIsStillFlaggedAfterLearning() {
        let (past, last) = history(count: 12, kmPerDay: 350)
        let entryID = UUID.v7()
        let entries = past + [fill(at(12, 12), last + 3_500, id: entryID)]
        #expect(!paceFlags(entries, entryID).isEmpty)
    }

    /// Below `paceLearningReadings` the check is off: a new car is not judged
    /// before the app has seen it driven. The order check still runs.
    @Test func theCheckIsOffUntilTheCarHasEnoughReadings() {
        let (past, last) = history(count: TimelineValidator.paceLearningReadings - 2, kmPerDay: 50)
        let entryID = UUID.v7()
        let entries = past + [fill(at(20, 12), last + 5_000, id: entryID)]
        #expect(TimelineValidator.paceLimit(for: entries, vehicle: vehicle(), calendar: calendar) == nil)
        #expect(paceFlags(entries, entryID).isEmpty)

        let oneMore = past + [fill(at(19, 12), last + 50), fill(at(20, 12), last + 5_050, id: entryID)]
        #expect(TimelineValidator.paceLimit(for: oneMore, vehicle: vehicle(), calendar: calendar) != nil)
        #expect(!paceFlags(oneMore, entryID).isEmpty)
    }

    /// A commuter's learned limit is the floor, a full day of motorway: a
    /// 700 km trip passes, 900 km in a day asks for a check.
    @Test func aCommuterGetsTheFloor() {
        let (past, last) = history(count: 12, kmPerDay: 50)
        #expect(TimelineValidator.paceLimit(for: past, vehicle: vehicle(), calendar: calendar)
            == TimelineValidator.paceLearnedFloorKmPerDay)
        let trip = UUID.v7()
        #expect(paceFlags(past + [fill(at(12, 12), last + 700, id: trip)], trip).isEmpty)
        #expect(!paceFlags(past + [fill(at(12, 12), last + 900, id: trip)], trip).isEmpty)
    }

    /// A heavy driver's learned limit is capped at the default.
    @Test func aHeavyDriverIsCappedAtTheDefault() {
        let (past, _) = history(count: 12, kmPerDay: 600)
        #expect(TimelineValidator.paceLimit(for: past, vehicle: vehicle(), calendar: calendar)
            == TimelineValidator.defaultPaceLimitKmPerDay)
    }

    /// A limit the user set is theirs (hard rule 13): it applies from the
    /// first pair, with no learning.
    @Test func aUserSetLimitAppliesAsSet() {
        let entryID = UUID.v7()
        let entries: [any Entry] = [fill(at(0, 12), 100_000), fill(at(1, 12), 100_400, id: entryID)]
        let own = vehicle(paceLimit: 300)
        #expect(TimelineValidator.paceLimit(for: entries, vehicle: own, calendar: calendar) == 300)
        #expect(!paceFlags(entries, entryID, vehicle: own).isEmpty)
    }

    /// The confirm screen's live caption asks the same rule: no pace warn for
    /// the motorway leg, none while the check is learning, and the warn for a
    /// distance over the limit a day apart.
    @Test func theLiveCaptionUsesTheSameRule() {
        func state(_ km: Int, from: Date, to: Date, limit: Double?) -> OdometerDelta.State? {
            OdometerDelta.evaluate(typed: 100_000 + km, lastKnown: 100_000, lastKnownDate: from,
                                   entryDate: to, paceLimitKmPerDay: limit, calendar: calendar)?.state
        }
        #expect(state(296, from: at(12, 22), to: at(13, 1), limit: 1_400) == .forward)
        #expect(state(10_000, from: at(12, 22), to: at(13, 1), limit: nil) == .forward)
        #expect(state(3_500, from: at(12, 12), to: at(13, 12), limit: 1_400) == .pace)
    }

    /// The range and the flags agree at the one-day minimum: two hours apart
    /// across midnight, one day's limit is valid at any instant and one more
    /// kilometre needs more than a day.
    @Test func theRangeAgreesWithTheFlagsAtTheOneDayMinimum() {
        let limited = vehicle(paceLimit: 500)
        let previousDate = at(30, 23)
        let entryID = UUID.v7()
        func entries(_ odometer: Int, _ date: Date = at(31, 1)) -> [any Entry] {
            [fill(previousDate, 100_000), fill(date, odometer, id: entryID), fill(at(60, 12), 102_000)]
        }
        let range = TimelineValidator.validate(entries: entries(100_500), vehicle: limited,
                                               calendar: calendar, pace: .vehicleLimit)
            .first { $0.entryID == entryID }?.validRange
        #expect(range?.odometer == .bounded(lower: 100_001, upper: 100_500))
        #expect(paceFlags(entries(100_500), entryID, vehicle: limited, pace: .vehicleLimit).isEmpty)
        #expect(!paceFlags(entries(100_501), entryID, vehicle: limited, pace: .vehicleLimit).isEmpty)

        // One day's limit: any date after the previous fill.
        if case .bounded(let lower, _) = range?.dates {
            #expect(lower == previousDate)
        } else {
            Issue.record("a bounded date range was expected")
        }
        // One kilometre more: the earliest valid instant is just past a day.
        let over = TimelineValidator.validate(entries: entries(100_501), vehicle: limited,
                                              calendar: calendar, pace: .vehicleLimit)
            .first { $0.entryID == entryID }?.validRange?.dates
        guard case .bounded(let earliest?, _) = over else {
            Issue.record("a lower date bound was expected"); return
        }
        #expect(earliest > previousDate + day)
        #expect(paceFlags(entries(100_501, earliest), entryID, vehicle: limited, pace: .vehicleLimit).isEmpty)
        #expect(!paceFlags(entries(100_501, earliest - 3_600), entryID, vehicle: limited,
                           pace: .vehicleLimit).isEmpty)
    }
}
