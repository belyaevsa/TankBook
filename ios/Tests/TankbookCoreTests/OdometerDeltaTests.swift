import Testing
import Foundation
@testable import TankbookCore

/// PJ.14 - the live "+N km since last" caption state (docs/DESIGN.md -> the
/// Pump Card; docs/VISION.md -> Fill-up log). The delta is a value in core so
/// the four states are asserted at L1: forward (typed > last, within pace),
/// equal (typed == last - neutral), backwards (typed < last - warn) and pace
/// (implied km/day over `paceLimitKmPerDay` - warn). The pace boundary and the
/// missing-input nils are pinned too, so the caption's behaviour is decided in
/// code and not left to a view that only XCUITest can reach.
@Suite("Odometer delta caption (PJ.14)")
struct OdometerDeltaTests {

    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_752_000_000)
    private var sixDaysAgo: Date { now.addingTimeInterval(-6 * day) }
    private let limit = 1500.0

    private func evaluate(typed: Int?, lastKnown: Int? = 119_486,
                          lastKnownDate: Date? = nil,
                          entryDate: Date? = nil) -> OdometerDelta? {
        OdometerDelta.evaluate(typed: typed,
                               lastKnown: lastKnown,
                               lastKnownDate: lastKnownDate ?? sixDaysAgo,
                               entryDate: entryDate ?? now,
                               paceLimitKmPerDay: limit)
    }

    // MARK: - The four states

    @Test("typed above last known within pace is forward")
    func forward() throws {
        let delta = try #require(evaluate(typed: 120_000))
        #expect(delta.km == 514)
        #expect(delta.state == .forward)
        #expect(!delta.state.isWarning)
    }

    @Test("typed equal to last known is the neutral equal state")
    func equal() throws {
        let delta = try #require(evaluate(typed: 119_486))
        #expect(delta.km == 0)
        #expect(delta.state == .equal)
        #expect(!delta.state.isWarning)
    }

    @Test("typed below last known is the backwards warn")
    func backwards() throws {
        let delta = try #require(evaluate(typed: 119_000))
        #expect(delta.km == -486)
        #expect(delta.state == .backwards)
        #expect(delta.state.isWarning)
    }

    @Test("an implied daily rate over the limit is the pace warn")
    func pace() throws {
        // 130 000 - 119 486 = 10 514 km over 6 days = 1 752/day > 1 500.
        let delta = try #require(evaluate(typed: 130_000))
        #expect(delta.km == 10_514)
        #expect(delta.state == .pace)
        #expect(delta.state.isWarning)
    }

    // MARK: - Boundaries

    @Test("a rate exactly at the limit stays forward")
    func paceAtLimitIsNotFlagged() throws {
        // 9 000 km over 6 days = 1 500/day exactly - `> limit`, never `>=`.
        let delta = try #require(evaluate(typed: 128_486))
        #expect(delta.state == .forward)
    }

    @Test("a same-date entry skips the pace check")
    func sameDateSkipsPace() throws {
        let delta = try #require(evaluate(typed: 130_000,
                                           lastKnownDate: now,
                                           entryDate: now))
        #expect(delta.state == .forward)
    }

    @Test("no last-known date skips the pace check")
    func noAnchorDateSkipsPace() throws {
        let delta = try #require(
            OdometerDelta.evaluate(typed: 200_000, lastKnown: 119_486,
                                   lastKnownDate: nil, entryDate: now,
                                   paceLimitKmPerDay: limit))
        #expect(delta.state == .forward)
    }

    // MARK: - Missing inputs

    @Test("no typed odometer returns nil")
    func noTypedValueIsNil() {
        #expect(evaluate(typed: nil) == nil)
    }

    @Test("no last-known value returns nil")
    func noLastKnownIsNil() {
        #expect(evaluate(typed: 120_000, lastKnown: nil) == nil)
    }

    // MARK: - The last-known derivation

    private let vehicle = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "Test", make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 82_000)

    private func fill(date: Date, odometer: Int) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: vehicle.id, date: date, odometer: odometer,
               money: nil, note: nil, attachments: [], provenance: .manual,
               conflict: .none, purchaseGroupId: nil, volumeL: 40,
               unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil, isFull: true,
               tankLevelAfterPct: nil, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    @Test("last known is the max odometer and that entry's date")
    func lastKnownDerivesMaxOdometerAndDate() {
        let old = fill(date: sixDaysAgo, odometer: 119_000)
        let newest = fill(date: now, odometer: 119_486)
        let known = OdometerLastKnown.lastKnown(in: [old, newest], vehicle: vehicle)
        #expect(known.odometer == 119_486)
        #expect(known.date == now)
    }

    @Test("last known uses the newest occurrence of the max odometer")
    func lastKnownPrefersTheNewestOccurrence() {
        // Two fills at the same max odometer (1989 fixture-style vs six days
        // ago): the caption's pace anchor must be the NEWEST one - an old
        // occurrence makes the implied daily pace tiny and the pace warn never
        // fires (the ConfirmManual suite's accumulated fixture fills exposed
        // this exact trap).
        let ancient = fill(date: Date(timeIntervalSince1970: 599_522_400), odometer: 119_486)
        let recent = fill(date: sixDaysAgo, odometer: 119_486)
        let known = OdometerLastKnown.lastKnown(in: [ancient, recent], vehicle: vehicle)
        #expect(known.odometer == 119_486)
        #expect(known.date == sixDaysAgo)
    }

    @Test("last known falls back to initialOdometer with no date when no entry has one")
    func lastKnownFallsBackToInitialOdometer() {
        let known = OdometerLastKnown.lastKnown(in: [], vehicle: vehicle)
        #expect(known.odometer == 82_000)
        #expect(known.date == nil)
    }
}
