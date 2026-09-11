import Testing
import Foundation
@testable import TankbookCore

// RV.117a: the valid RANGE behind a timeline conflict. These assert the
// ENDPOINTS of the intervals `EntryValidation.validRange` returns - never that
// "a range exists" - and the equivalence that keeps the range and the flags
// from disagreeing: a value inside validates clean, a value outside flags.

private let day: TimeInterval = 86_400
private let base = Date(timeIntervalSince1970: 1_752_000_000)

private func vehicle(paceLimit: Double = 1500) -> Vehicle {
    Vehicle(
        id: UUID.v7(),
        createdAt: base,
        updatedAt: base,
        deletedAt: nil,
        name: "Test car",
        make: nil,
        model: nil,
        year: nil,
        plate: nil,
        powertrain: .ice,
        fuelKinds: [.petrol95],
        tankCapacityL: nil,
        batteryCapacityKWh: nil,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil,
        paceLimitKmPerDay: paceLimit
    )
}

private func fill(date: Date, odometer: Int?, id: UUID = UUID.v7()) -> FillUp {
    var entry = FillUp(
        id: id,
        createdAt: date,
        updatedAt: date,
        deletedAt: nil,
        vehicleId: UUID.v7(),
        date: date,
        odometer: 0,
        money: nil,
        note: nil,
        attachments: [],
        provenance: .manual,
        conflict: .none,
        purchaseGroupId: nil,
        volumeL: 40,
        unitPrice: nil,
        fuelKind: .petrol95,
        fuelGrade: nil,
        isFull: true,
        tankLevelAfterPct: nil,
        stationId: nil,
        crossCheck: .notApplicable,
        extraction: nil
    )
    entry.odometer = odometer
    return entry
}

private func validation(_ entries: [any Entry], _ id: UUID, limit: Double = 1500)
    -> TimelineValidator.EntryValidation? {
    TimelineValidator.validate(entries: entries, vehicle: vehicle(paceLimit: limit))
        .first { $0.entryID == id }
}

/// The flags the entry at `id` produces when it holds `odometer` at `date`.
/// Filtered to the order/pace TIMELINE kinds: these tests are about the valid
/// range's order/pace equivalence, and the CHECK 5 consumption hint is a
/// different question (its own suite is `RV218ConsumptionOutlierTests`).
private func flags(entries: [any Entry], id: UUID, odometer: Int?, date: Date,
                   limit: Double = 1500) -> [TimelineValidator.Flag] {
    var copy = entries
    guard let index = copy.firstIndex(where: { $0.id == id }) else { return [] }
    copy[index].odometer = odometer
    copy[index].date = date
    return (validation(copy, id, limit: limit)?.flags ?? [])
        .filter { $0.kind != .consumption }
}

// MARK: - The owner's own numbers: the upper end is the PACE bound, not next - 1

@Test func drivvoUpperBoundIsPaceDerivedNotNextMinusOne() {
    // docs/COMPETITORS.md's five readings: 489 590 / 490 500 / 490 200 [flagged] /
    // 491 206 / 491 791 across 14/06-24/08. The flagged entry (490 200) is BELOW
    // its previous reading 490 500, and the stated upper end is 490 983 - not the
    // next reading 491 206 (order alone would allow up to 491 205). Reproduce that
    // with a 7-day gap to the previous reading and a 69 km/day limit:
    // 490 500 + 69 x 7 = 490 983, which binds tighter than 491 206 - 1.
    let flaggedID = UUID.v7()
    let entries: [any Entry] = [
        fill(date: base + 0 * day, odometer: 489_590),
        fill(date: base + 23 * day, odometer: 490_500),
        fill(date: base + 30 * day, odometer: 490_200, id: flaggedID),
        fill(date: base + 60 * day, odometer: 491_206),
        fill(date: base + 72 * day, odometer: 491_791),
    ]

    let range = validation(entries, flaggedID, limit: 69)?.validRange
    #expect(range?.odometer == .bounded(lower: 490_501, upper: 490_983))
    // 491 205 would be order-fine (strictly below 491 206) - only the pace bound
    // rules it out, which is exactly the point of the row.
    #expect(range?.odometer != .bounded(lower: 490_501, upper: 491_205))
}

@Test func drivvoNeighbourhoodFlagsExactlyOutsideTheInterval() {
    let flaggedID = UUID.v7()
    func entriesWith(_ odo: Int) -> [any Entry] {
        [
            fill(date: base + 0 * day, odometer: 489_590),
            fill(date: base + 23 * day, odometer: 490_500),
            fill(date: base + 30 * day, odometer: odo, id: flaggedID),
            fill(date: base + 60 * day, odometer: 491_206),
            fill(date: base + 72 * day, odometer: 491_791),
        ]
    }

    // 490 200 (the imported value, below the previous) flags by order.
    #expect(flags(entries: entriesWith(490_200), id: flaggedID, odometer: 490_200,
                  date: base + 30 * day, limit: 69).isEmpty == false)
    // Endpoints: 490 501 and 490 983 are inside (never flagged), the values one
    // km outside them always are.
    #expect(flags(entries: entriesWith(490_501), id: flaggedID, odometer: 490_501,
                  date: base + 30 * day, limit: 69).isEmpty)
    #expect(flags(entries: entriesWith(490_500), id: flaggedID, odometer: 490_500,
                  date: base + 30 * day, limit: 69).isEmpty == false)
    #expect(flags(entries: entriesWith(490_983), id: flaggedID, odometer: 490_983,
                  date: base + 30 * day, limit: 69).isEmpty)
    #expect(flags(entries: entriesWith(490_984), id: flaggedID, odometer: 490_984,
                  date: base + 30 * day, limit: 69).isEmpty == false)
    // 491 205 is inside the ORDER bounds yet still flags - the pace bound is real.
    #expect(flags(entries: entriesWith(491_205), id: flaggedID, odometer: 491_205,
                  date: base + 30 * day, limit: 69).isEmpty == false)
}

@Test func drivvoOutOfOrderOdometerHasNoValidDateBetweenItsNeighbours() {
    let flaggedID = UUID.v7()
    let entries: [any Entry] = [
        fill(date: base + 0 * day, odometer: 489_590),
        fill(date: base + 23 * day, odometer: 490_500),
        fill(date: base + 30 * day, odometer: 490_200, id: flaggedID),
        fill(date: base + 60 * day, odometer: 491_206),
        fill(date: base + 72 * day, odometer: 491_791),
    ]

    // 490 200 sits below its previous reading, so NO date between 490 500's and
    // 491 206's entries keeps it consistent - the odometer is the field to
    // question, and the empty date side is what says so.
    let range = validation(entries, flaggedID, limit: 69)?.validRange
    #expect(range?.dates == ValidRange<Date>.none)
}

// MARK: - Open ends are first-class (nil), never a sentinel

@Test func newestEntryDateIntervalHasAnOpenUpperBound() {
    // The newest entry has no `next`, so nothing bounds its date from above: a
    // reading 400 km above its previous entry at <= 20 km/day is valid on any
    // date no earlier than 20 days after the previous one - including far later.
    let newestID = UUID.v7()
    let entries: [any Entry] = [
        fill(date: base + 0 * day, odometer: 100_000),
        fill(date: base + 30 * day, odometer: 100_400, id: newestID),
    ]
    let limit = 20.0

    let range = validation(entries, newestID, limit: limit)?.validRange
    #expect(range?.dates == .bounded(lower: base + 20 * day, upper: nil))

    // Exactly at the pace lower bound: implied 20 km/day == the limit, clean.
    #expect(flags(entries: entries, id: newestID, odometer: 100_400,
                  date: base + 20 * day, limit: limit).isEmpty)
    // One day earlier than the pace bound lets the entry lag the previous one at
    // more than 20 km/day -> pace flag. Later dates have no upper neighbour.
    #expect(flags(entries: entries, id: newestID, odometer: 100_400,
                  date: base + 19 * day, limit: limit).isEmpty == false)
    #expect(flags(entries: entries, id: newestID, odometer: 100_400,
                  date: base + 60 * day, limit: limit).isEmpty)
}

@Test func oldestEntryDateIntervalHasAnOpenLowerBound() {
    // The oldest entry has no `previous`, so nothing bounds its date from below:
    // the only constraint is reaching the next reading within the pace limit.
    let oldestID = UUID.v7()
    let entries: [any Entry] = [
        fill(date: base + 0 * day, odometer: 100_000, id: oldestID),
        fill(date: base + 40 * day, odometer: 100_600),
    ]
    let limit = 20.0

    let range = validation(entries, oldestID, limit: limit)?.validRange
    #expect(range?.dates == .bounded(lower: nil, upper: base + 10 * day))

    // Dates well before its stored date are valid (open lower); the upper bound
    // is 10 days after `base` because 600 km at <= 20 km/day needs 30 days of
    // road before the 40-day-ahead next reading.
    #expect(flags(entries: entries, id: oldestID, odometer: 100_000,
                  date: base - 5 * day, limit: limit).isEmpty)
    #expect(flags(entries: entries, id: oldestID, odometer: 100_000,
                  date: base + 10 * day, limit: limit).isEmpty)
    #expect(flags(entries: entries, id: oldestID, odometer: 100_000,
                  date: base + 11 * day, limit: limit).isEmpty == false)
}

@Test func singleEntryTimelineHasFullyOpenRanges() {
    // No neighbours at all: every reading and every date is consistent, expressed
    // as open bounds (nil), never as a sentinel number or as `.none`.
    let onlyID = UUID.v7()
    let entries: [any Entry] = [fill(date: base, odometer: 100_000, id: onlyID)]
    let range = validation(entries, onlyID)?.validRange
    #expect(range?.odometer == .bounded(lower: nil, upper: nil))
    #expect(range?.dates == .bounded(lower: nil, upper: nil))
}

// MARK: - A same-day neighbour contributes no pace bound (the days > 0 guard)

@Test func sameDayPreviousContributesOrderOnlyNotAPaceBound() {
    // Previous and entry share a timestamp, so the pace check toward the previous
    // is skipped (docs/SCHEMA.md CHECK 2: `days > 0`). The interval is bounded by
    // order alone on that side - had the previous been a day earlier, the 10
    // km/day limit would have collapsed the range to nothing.
    let entryID = UUID.v7()
    let sharedDay = base + 30 * day
    let entries: [any Entry] = [
        fill(date: sharedDay, odometer: 100_000),
        fill(date: sharedDay, odometer: 100_400, id: entryID),
        fill(date: base + 50 * day, odometer: 101_000),
    ]
    let limit = 10.0

    let range = validation(entries, entryID, limit: limit)?.validRange
    // Lower: the next reading 101 000 at <= 10 km/day over its 20-day gap allows
    // any reading >= 100 800. Upper: strictly below 101 000 (next - 1) - the
    // same-day previous adds no pace ceiling above 100 000.
    #expect(range?.odometer == .bounded(lower: 100_800, upper: 100_999))

    #expect(flags(entries: entries, id: entryID, odometer: 100_800,
                  date: sharedDay, limit: limit).isEmpty)
    #expect(flags(entries: entries, id: entryID, odometer: 100_999,
                  date: sharedDay, limit: limit).isEmpty)
    #expect(flags(entries: entries, id: entryID, odometer: 100_799,
                  date: sharedDay, limit: limit).isEmpty == false)
    #expect(flags(entries: entries, id: entryID, odometer: 101_000,
                  date: sharedDay, limit: limit).isEmpty == false)
}

// MARK: - Equivalence: inside the interval never flags, outside always does

@Test func equivalenceHoldsWhenOrderBindsTheLowerEndAndPaceTheUpper() {
    // prev 100 000 on day 0; the next reading is so far away (day 400) that the
    // pace-toward-next lower bound falls below the order bound. So the interval
    // is [100 001 (order), 100 000 + 50 x 30 = 101 500 (pace)].
    let entryID = UUID.v7()
    let entryDay = base + 30 * day
    func entriesWith(_ odo: Int) -> [any Entry] {
        [
            fill(date: base + 0 * day, odometer: 100_000),
            fill(date: entryDay, odometer: odo, id: entryID),
            fill(date: base + 400 * day, odometer: 106_000),
        ]
    }
    let limit = 50.0
    let range = validation(entriesWith(100_100), entryID, limit: limit)?.validRange
    #expect(range?.odometer == .bounded(lower: 100_001, upper: 101_500))

    // Drive the boundary itself and one step either side, plus an interior value.
    let cases: [(Int, Bool)] = [
        (100_000, false),   // below the lower bound: equals the previous -> order
        (100_001, true),    // the lower bound
        (101_000, true),    // interior
        (101_500, true),    // the upper bound (implied pace exactly 50 km/day)
        (101_501, false),   // above the upper bound: implied pace over the limit
    ]
    for (odo, expectClean) in cases {
        #expect(flags(entries: entriesWith(odo), id: entryID, odometer: odo,
                      date: entryDay, limit: limit).isEmpty == expectClean,
                "odometer \(odo)")
    }
}

@Test func equivalenceHoldsWhenPaceBindsBothEndsToASingleValue() {
    // prev 100 000 (day 0) -> entry -> next 103 000 (day 60), 30 days each side,
    // limit 50: the pace ceiling from the previous is 101 500 and the pace floor
    // toward the next is also 101 500 - a single consistent reading.
    let entryID = UUID.v7()
    let entryDay = base + 30 * day
    func entriesWith(_ odo: Int) -> [any Entry] {
        [
            fill(date: base + 0 * day, odometer: 100_000),
            fill(date: entryDay, odometer: odo, id: entryID),
            fill(date: base + 60 * day, odometer: 103_000),
        ]
    }
    let limit = 50.0
    let range = validation(entriesWith(100_500), entryID, limit: limit)?.validRange
    #expect(range?.odometer == .bounded(lower: 101_500, upper: 101_500))

    let cases: [(Int, Bool)] = [
        (101_499, false),
        (101_500, true),
        (101_501, false),
    ]
    for (odo, expectClean) in cases {
        #expect(flags(entries: entriesWith(odo), id: entryID, odometer: odo,
                      date: entryDay, limit: limit).isEmpty == expectClean,
                "odometer \(odo)")
    }
}

// MARK: - An inconsistent neighbourhood is `.none`, never an inverted range

@Test func inconsistentNeighbourhoodYieldsNoValidOdometerOrDate() {
    // prev 100 000 (day 0) -> entry (day 5) -> next 101 000 (day 6) at a 50 km/day
    // limit: the previous reading allows only <= 100 250 by day 5, while reaching
    // the next reading needs >= 100 950 by day 5. The constraints cross - no value
    // fits, so the interval is `.none`, not "between 100 950 and 100 250".
    let entryID = UUID.v7()
    let entryDay = base + 5 * day
    let entries: [any Entry] = [
        fill(date: base + 0 * day, odometer: 100_000),
        fill(date: entryDay, odometer: 100_500, id: entryID),
        fill(date: base + 6 * day, odometer: 101_000),
    ]
    let limit = 50.0

    let range = validation(entries, entryID, limit: limit)?.validRange
    #expect(range?.odometer == ValidRange<Int>.none)
    #expect(range?.dates == ValidRange<Date>.none)

    // And the equivalence still holds over a vacuous interval: every reading flags.
    for odo in [100_001, 100_500, 100_900, 100_999] {
        #expect(flags(entries: entries, id: entryID, odometer: odo,
                      date: entryDay, limit: limit).isEmpty == false,
                "odometer \(odo)")
    }
}

// MARK: - The date interval for a fixed odometer, at its endpoints

@Test func dateIntervalEndpointsAreExactInBothDirections() {
    // prev 100 000 (day 0) -> entry 100 500 -> next 101 000 (day 60), limit 20:
    // the entry needs >= 25 days after the previous reading (500 km at <= 20/day)
    // and <= 35 days before the next - the dates [day 25, day 35] are the only
    // consistent ones.
    let entryID = UUID.v7()
    func entriesOn(_ entryDate: Date) -> [any Entry] {
        [
            fill(date: base + 0 * day, odometer: 100_000),
            fill(date: entryDate, odometer: 100_500, id: entryID),
            fill(date: base + 60 * day, odometer: 101_000),
        ]
    }
    let limit = 20.0
    let stored = validation(entriesOn(base + 30 * day), entryID, limit: limit)?.validRange
    #expect(stored?.dates == .bounded(lower: base + 25 * day, upper: base + 35 * day))

    // Both endpoints are inclusive (implied pace == the limit is not flagged) and
    // one step outside either end flags.
    #expect(flags(entries: entriesOn(base + 25 * day), id: entryID, odometer: 100_500,
                  date: base + 25 * day, limit: limit).isEmpty)
    #expect(flags(entries: entriesOn(base + 25 * day - 3600), id: entryID, odometer: 100_500,
                  date: base + 25 * day - 3600, limit: limit).isEmpty == false)
    #expect(flags(entries: entriesOn(base + 35 * day), id: entryID, odometer: 100_500,
                  date: base + 35 * day, limit: limit).isEmpty)
    #expect(flags(entries: entriesOn(base + 35 * day + 3600), id: entryID, odometer: 100_500,
                  date: base + 35 * day + 3600, limit: limit).isEmpty == false)
}

// MARK: - Derived, never stored; present whether or not the entry flags

@Test func validRangeIsNilOnlyForEntriesWithoutAnOdometer() {
    var noOdo = fill(date: base, odometer: nil)
    noOdo.odometer = nil
    let earlier = fill(date: base + 5 * day, odometer: 100_000)
    let withOdo = fill(date: base + 20 * day, odometer: 101_000)
    let entries: [any Entry] = [noOdo, earlier, withOdo]

    #expect(validation(entries, noOdo.id)?.validRange == nil)
    // A clean, unflagged entry still gets its range - the chart (RV.117b) draws
    // the neighbourhood, not just the offenders. The upper bound is the pace
    // ceiling from its previous reading (100 000 + 1500 x 15 days).
    #expect(validation(entries, withOdo.id)?.validRange?.odometer ==
        .bounded(lower: 100_001, upper: 122_500))
}
