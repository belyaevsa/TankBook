import Testing
import Foundation
@testable import TankbookCore

/// The Home derived-stats type (docs/ERRORS.md -> Home, docs/SCHEMA.md ->
/// consumption). The honesty rule under test: a vital that needs data is
/// ABSENT (nil), never zero - and the engine's values are passed through
/// unchanged, because Home does no arithmetic of its own (hard rule 2).
struct HomeStatsTests {

    // A fixed "now" so month/year windows are deterministic: 2025-07-06.
    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: asOf - 40 * day, updatedAt: asOf - 40 * day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(date: Date, odometer: Int, litres: Double, isFull: Bool,
                             unitPrice: Decimal? = nil,
                             conflict: ConflictState = .none) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: conflict,
            purchaseGroupId: nil, volumeL: litres, unitPrice: unitPrice,
            fuelKind: .petrol95, fuelGrade: nil, isFull: isFull,
            tankLevelAfterPct: isFull ? 100 : nil, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    // MARK: - Zero entries: every data-hungry vital is ABSENT, not zero

    @Test func zeroEntriesExposeNoVitals() {
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [], asOf: Self.asOf)

        #expect(stats.headline == nil)
        #expect(stats.lifetime == nil)
        #expect(stats.costPerKm == nil)
        #expect(stats.monthSpend == nil)
        #expect(stats.lastUnitPrice == nil)
        #expect(stats.bestThisYear == nil)
        #expect(stats.needsAnotherFullTank == false)
        #expect(stats.hasEntries == false)
        #expect(stats.excludedEntryCount == 0)
        #expect(stats.updatedAt == nil)
        // The only figure with data is the vehicle's own baseline odometer -
        // real user-entered data, not a fabricated stat.
        #expect(stats.odometer == 118_000)
    }

    // MARK: - One fill-up, no segment yet: the D4 case is signalled

    @Test func singleFillSignalsD4HintAndNoHeadline() {
        let single = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 118_000,
                          litres: 42, isFull: true,
                          unitPrice: Decimal(string: "1.679")!)
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [single], asOf: Self.asOf)

        // A full tank opens a segment but does not close one: no headline.
        #expect(stats.headline == nil)
        #expect(stats.needsAnotherFullTank == true)
        #expect(stats.hasEntries == true)
        // The vitals that DO have data are present...
        #expect(stats.lastUnitPrice == Decimal(string: "1.679"))
        #expect(stats.monthSpend != nil)
        #expect(stats.odometer == 118_000)
        #expect(stats.updatedAt == single.date)
        // ...and the ones that do not are absent, not zero.
        #expect(stats.lifetime == nil)
        #expect(stats.costPerKm == nil)
        #expect(stats.bestThisYear == nil)
    }

    @Test func partialFillAloneDoesNotClaimD4Hint() {
        // No full tank yet: the "one more full tank" hint would be a lie.
        let partial = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 118_000,
                           litres: 20, isFull: false)
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [partial], asOf: Self.asOf)
        #expect(stats.headline == nil)
        #expect(stats.needsAnotherFullTank == false)
    }

    // MARK: - A closed segment produces a first-estimate headline

    @Test func closedSegmentAppearsAndIsFirstEstimate() {
        let f1 = Self.fill(date: Self.asOf - 16 * Self.day, odometer: 118_000, litres: 42, isFull: true)
        let f2 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_800, litres: 40, isFull: true)
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [f1, f2], asOf: Self.asOf)

        #expect(stats.headline != nil)
        #expect(stats.needsAnotherFullTank == false)
        // One segment is below the floor of 3: the honest label is a first
        // estimate, never a fake "last N months".
        #expect(stats.isFirstEstimate == true)
        if case .firstEstimate(let cycles) = stats.headline?.label {
            #expect(cycles == 1)
        } else {
            #expect(Bool(false), "headline label should be firstEstimate")
        }
    }

    @Test func threeSegmentsSatisfyTheFloorWithWindowLabel() {
        let f1 = Self.fill(date: Self.asOf - 35 * Self.day, odometer: 118_000, litres: 41, isFull: true)
        let f2 = Self.fill(date: Self.asOf - 16 * Self.day, odometer: 118_800, litres: 42, isFull: true)
        let f3 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 119_600, litres: 40, isFull: true)
        let f4 = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 120_400, litres: 43, isFull: true)
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [f1, f2, f3, f4], asOf: Self.asOf)

        #expect(stats.headline != nil)
        #expect(stats.isFirstEstimate == false)
        if case .window(let months) = stats.headline?.label {
            #expect(months == 3)
        } else {
            #expect(Bool(false), "headline label should be a window")
        }
        // Best this year: the year's segments close Jul 1 (5.0) and Jul 5
        // (43/800*100 = 5.375); the June closes are outside the year window.
        #expect(abs((stats.bestThisYear ?? -1) - 5.0) < 0.001)
        // The current month holds two fills.
        #expect(stats.monthSpend != nil)
    }

    @Test func conflictFlaggedEntryCountsAsExcluded() {
        let clean = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_800, litres: 40, isFull: true)
        let flagged = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 119_600, litres: 42, isFull: true,
                           conflict: .flagged(kind: .order, detectedAt: Self.asOf))
        let stats = HomeStats(vehicle: Self.vehicle(), entries: [clean, flagged], asOf: Self.asOf)
        #expect(stats.excludedEntryCount == 1)
    }

    // MARK: - The engine's values are passed through unchanged

    @Test func engineValuesPassThroughUnchanged() {
        let f1 = Self.fill(date: Self.asOf - 35 * Self.day, odometer: 118_000, litres: 41, isFull: true)
        let f2 = Self.fill(date: Self.asOf - 16 * Self.day, odometer: 118_800, litres: 42, isFull: true)
        let f3 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 119_600, litres: 40, isFull: true)
        let f4 = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 120_400, litres: 43, isFull: true)
        let entries: [any Entry] = [f1, f2, f3, f4]
        let stats = HomeStats(vehicle: Self.vehicle(), entries: entries, asOf: Self.asOf)

        let segments = ConsumptionEngine.segments(for: entries.compactMap { $0 as? FillUp },
                                                  tankCapacityL: Self.vehicle().tankCapacityL)
        // Home does no arithmetic of its own: the stats ARE the engine's output.
        #expect(stats.headline == ConsumptionEngine.headline(segments: segments, asOf: Self.asOf))
        #expect(stats.lifetime == ConsumptionEngine.lifetime(segments: segments))
        #expect(stats.costPerKm == ConsumptionEngine.costPerKm(entries: entries, asOf: Self.asOf))
    }
}
