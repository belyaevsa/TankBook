import Testing
import Foundation
@testable import TankbookCore

// RV.192: the pace bound is a CALENDAR-DAY rule, not a fractional-instant one.
// docs/SCHEMA.md (Validation): "a same-day neighbour contributes no pace bound".
// Two entries hours apart on one day divide a real odometer delta by a fraction
// of a day, so the guard cannot be the instant between them. Every fixture pins
// a UTC calendar rather than inheriting the machine's - the named trap is a test
// that passes in Tallinn and fails in CI.
//
// Oracle for every expectation here: the sentence above (and its valid-range
// twin in docs/SCHEMA.md -> Validation -> Valid range).

/// UTC so "same day" never depends on the machine's timezone.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}()

/// A midnight-UTC anchor: 2025-07-14 00:00:00 UTC.
private let base = Date(timeIntervalSince1970: 1_752_451_200)
private let day: TimeInterval = 86_400

/// A date on `dayOffset` at `hour`:00 UTC.
private func at(_ dayOffset: Int, _ hour: Int) -> Date {
    base + Double(dayOffset) * day + Double(hour) * 3_600
}

private func vehicle(paceLimit: Double = 1500) -> Vehicle {
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

private func fill(date: Date, odometer: Int, id: UUID = UUID.v7()) -> FillUp {
    var entry = FillUp(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: UUID.v7(), date: date, odometer: 0, money: nil, note: nil,
        attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil, volumeL: 40, unitPrice: nil, fuelKind: .petrol95,
        fuelGrade: nil, isFull: true, tankLevelAfterPct: nil, stationId: nil,
        crossCheck: .notApplicable, extraction: nil
    )
    entry.odometer = odometer
    return entry
}

private func validation(_ entries: [any Entry], _ id: UUID,
                        limit: Double = 1500) -> TimelineValidator.EntryValidation? {
    TimelineValidator.validate(entries: entries, vehicle: vehicle(paceLimit: limit),
                               calendar: calendar)
        .first { $0.entryID == id }
}

/// The flags the entry at `id` produces when it holds `odometer` at `date`.
/// Filtered to the order/pace TIMELINE kinds: these tests are about the
/// calendar-day pace bound, and the CHECK 5 consumption hint is a different
/// question (its own suite is `RV218ConsumptionOutlierTests`).
private func flags(entries: [any Entry], id: UUID, odometer: Int?, date: Date,
                   limit: Double = 1500) -> [TimelineValidator.Flag] {
    var copy = entries
    guard let index = copy.firstIndex(where: { $0.id == id }) else { return [] }
    copy[index].odometer = odometer
    copy[index].date = date
    return (validation(copy, id, limit: limit)?.flags ?? [])
        .filter { $0.kind != .consumption }
}

@Suite("RV.192 same-day pace bound")
struct RV192SameDayPaceTests {

    @Test func sameCalendarDayHoursApartProduceNoPaceFlag() {
        // 09:00 -> 18:00 on one day, 300 km apart, at a 100 km/day limit. The
        // fractional gap is 0.375 days, so the old instant guard computed 800
        // km/day and flagged; a same-day neighbour contributes no pace bound.
        let entryID = UUID.v7()
        let entries: [any Entry] = [
            fill(date: at(30, 9), odometer: 100_000),
            fill(date: at(30, 18), odometer: 100_300, id: entryID),
            fill(date: at(50, 9), odometer: 101_000),
        ]
        let result = validation(entries, entryID, limit: 100)
        let pace = result?.flags.compactMap { flag -> Double? in
            if case .pace(_, let kmPerDay, _) = flag.detail { return kmPerDay }
            return nil
        }
        #expect(result?.flags.isEmpty == true,
                "a same-day neighbour contributes no pace bound (docs/SCHEMA.md, Validation); got pace \(String(describing: pace))")
    }

    @Test func adjacentCalendarDaysNineHoursApartStillGetTheirPaceBound() {
        // 21:00 -> 06:00, nine hours apart but across midnight, so they are on
        // ADJACENT calendar days and the pace bound applies: 300 km / 0.375 days
        // = 800 km/day > 100. A `days >= 1` guard on the fractional value would
        // wrongly drop this (the named vacuous trap).
        let entryID = UUID.v7()
        let entries: [any Entry] = [
            fill(date: at(30, 21), odometer: 100_000),
            fill(date: at(31, 6), odometer: 100_300, id: entryID),
            fill(date: at(60, 21), odometer: 101_000),
        ]
        #expect(validation(entries, entryID, limit: 100)?
            .flags.contains { $0.kind == .pace } == true,
            "a pair on different calendar days keeps its pace bound however short the gap")
    }

    @Test func sameDayFallingReadingIsStillOrderFlagged() {
        // A reading that FALLS between two same-day entries is still wrong: the
        // same-day rule drops only the pace bound, never the order bound.
        let entryID = UUID.v7()
        let entries: [any Entry] = [
            fill(date: at(30, 9), odometer: 100_300),
            fill(date: at(30, 18), odometer: 100_000, id: entryID),
            fill(date: at(50, 9), odometer: 101_000),
        ]
        let result = validation(entries, entryID, limit: 100)
        #expect(result?.flags.contains { $0.kind == .order } == true,
                "a falling same-day reading is still order-flagged (RV.186 holds)")
        #expect(result?.flags.contains { $0.kind == .pace } == false,
                "and the same-day pair adds no pace flag of its own")
    }

    @Test func sameDayValidRangeAndFlagsAgree() {
        // previous and entry share a day; next is 20 days later. limit 500 puts
        // the previous pace bound on the SAME day (300/500 = 0.6 day), so the
        // range must widen to the neighbour's instant rather than exclude the
        // same-day reading - the odometer side and the date side both.
        let entryID = UUID.v7()
        let previousDate = at(30, 9)
        let entryDate = at(30, 18)
        let nextDate = at(50, 9)
        let limit = 500.0
        // 500 km to the next reading at a 500 km/day limit is exactly one day,
        // so the pace endpoint is a whole instant with no floating-point drift.
        func entriesWith(_ odometer: Int) -> [any Entry] {
            [
                fill(date: previousDate, odometer: 100_000),
                fill(date: entryDate, odometer: odometer, id: entryID),
                fill(date: nextDate, odometer: 100_800),
            ]
        }

        let range = validation(entriesWith(100_300), entryID, limit: limit)?.validRange
        // previous same-day -> order lower only (100 001); next is far enough
        // that its pace floor does not bind; upper is the next order bound.
        #expect(range?.odometer == .bounded(lower: 100_001, upper: 100_799))
        // The entry's own value is inside the suggested range and clean.
        #expect(flags(entries: entriesWith(100_300), id: entryID, odometer: 100_300,
                      date: entryDate, limit: limit).isEmpty)

        // Odometer endpoints: clean at the bounds, flagged one step outside.
        #expect(flags(entries: entriesWith(100_001), id: entryID, odometer: 100_001,
                      date: entryDate, limit: limit).isEmpty)
        #expect(flags(entries: entriesWith(100_000), id: entryID, odometer: 100_000,
                      date: entryDate, limit: limit).isEmpty == false)
        #expect(flags(entries: entriesWith(100_799), id: entryID, odometer: 100_799,
                      date: entryDate, limit: limit).isEmpty)
        #expect(flags(entries: entriesWith(100_800), id: entryID, odometer: 100_800,
                      date: entryDate, limit: limit).isEmpty == false)

        // Date side: the previous pace bound is same-day, so the lower end is
        // the previous instant itself; the upper end is the next pace bound.
        let dateUpper = nextDate.addingTimeInterval(-500 / limit * 86_400)
        #expect(range?.dates == .bounded(lower: previousDate, upper: dateUpper))
        #expect(flags(entries: entriesWith(100_300), id: entryID, odometer: 100_300,
                      date: previousDate, limit: limit).isEmpty)
        #expect(flags(entries: entriesWith(100_300), id: entryID, odometer: 100_300,
                      date: previousDate - 3_600, limit: limit).isEmpty == false)
        #expect(flags(entries: entriesWith(100_300), id: entryID, odometer: 100_300,
                      date: dateUpper, limit: limit).isEmpty)
        #expect(flags(entries: entriesWith(100_300), id: entryID, odometer: 100_300,
                      date: dateUpper + 3_600, limit: limit).isEmpty == false)
    }

    @Test func sameDaySuppressionIsCountedForTheLogEvent() {
        let entryID = UUID.v7()
        let entries: [any Entry] = [
            fill(date: at(30, 9), odometer: 100_000),
            fill(date: at(30, 18), odometer: 100_300, id: entryID),
        ]
        #expect(validation(entries, entryID, limit: 100)?.sameDayPaceSuppressions == 1,
                "the suppressed pace comparison is counted so the log can answer it")
    }
}
