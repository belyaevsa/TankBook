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

    private static func vehicle(homeCurrency: CurrencyCode = .eur) -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: asOf - 40 * day, updatedAt: asOf - 40 * day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: homeCurrency,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(date: Date, odometer: Int, litres: Double, isFull: Bool,
                             unitPrice: Decimal? = nil,
                             money: Money? = nil,
                             conflict: ConflictState = .none) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: money ?? Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .eur),
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
        #expect(stats.lastUnitPrice == UnitPriceFigure(amount: Decimal(string: "1.679")!,
                                                       currency: .eur),
                "a same-currency fill keeps its price and its own currency")
        #expect(stats.monthSpend != nil)
        #expect(stats.odometer == 118_000)
        #expect(stats.updatedAt == single.date)
        // ...and the ones that do not are absent, not zero.
        #expect(stats.lifetime == nil)
        #expect(stats.costPerKm == nil)
        #expect(stats.bestThisYear == nil)
    }

    /// RV.43: the single-fill SEED date must survive the 1st-6th of a month.
    /// `monthSpend` counts only entries inside `asOf`'s calendar month, and a
    /// relative "6 days ago" date crosses the boundary early in a month - so
    /// the spend tile the D4 state exists to show vanished on those days. The
    /// seed pins the fill to the start of the month it runs in; that date is
    /// inside the window on ANY run date, including the 1st.
    @Test func singleFillSeedPinnedToMonthStartCountsOnTheFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // A run on the 1st shortly after midnight: `asOf` here is "now".
        let firstOfMonth = calendar.date(
            from: DateComponents(year: 2025, month: 7, day: 1, hour: 0, minute: 30))!
        let monthStart = calendar.dateInterval(of: .month, for: firstOfMonth)!.start

        // The fix: the fill sits on the month's start - inside the window.
        let pinned = Self.fill(date: monthStart, odometer: 118_000, litres: 42, isFull: true)
        let fixed = HomeStats(vehicle: Self.vehicle(), entries: [pinned],
                              asOf: firstOfMonth, calendar: calendar)
        #expect(fixed.monthSpend != nil,
                "a fill pinned to the 1st must count towards that month's spend")

        // The old seed: `daysAgo: 6` from the 1st lands in the PREVIOUS month.
        let drifted = Self.fill(date: firstOfMonth - 6 * Self.day,
                                odometer: 118_000, litres: 42, isFull: true)
        let broken = HomeStats(vehicle: Self.vehicle(), entries: [drifted],
                               asOf: firstOfMonth, calendar: calendar)
        #expect(broken.monthSpend == nil,
                "6 days before the 1st is last month - the spend tile would vanish (RV.43)")
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

    // MARK: - RV.29: a foreign price never wears the home symbol

    /// The reported defect: a RUB-home car's foreign EUR fill with NO rate yet
    /// (F9). The old code returned the raw `1.919` and Home stamped `₽` on it -
    /// a number and a symbol from two different currencies (hard rule 3). There
    /// is no converted home price while the rate is pending, so the vital must
    /// be `nil`: the tile is omitted (the F9 footnote explains why), it is
    /// never a home-currency lie.
    @Test func foreignFillWithNoRateProducesNoHomeCurrencyPrice() {
        let pendingEUR = Money(amount: Decimal(string: "51.81")!, currency: .eur, homeCurrency: .rub)
        let foreign = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 118_000,
                                litres: 27, isFull: true,
                                unitPrice: Decimal(string: "1.919")!,
                                money: pendingEUR)
        let stats = HomeStats(vehicle: Self.vehicle(homeCurrency: .rub),
                              entries: [foreign], asOf: Self.asOf)

        #expect(stats.pendingRateCount == 1)
        #expect(stats.lastUnitPrice == nil,
                "a rate-pending foreign fill must not produce a home-currency price (was the RV.29 bug)")
    }

    /// A foreign fill WITH its rate snapshot converts by its own immutable rate
    /// into the vehicle's home currency - the number AND the symbol change
    /// together, so `1.919 EUR` reads `191.9 ₽` (rate 0.01 EUR/RUB), never a
    /// bare original under a RUB stamp.
    @Test func foreignFillWithRateConvertsToHomeCurrencyFigure() {
        let date = Self.asOf - 2 * Self.day
        let foreign = Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .rub)
            .converted(using: RateSnapshot(rate: Decimal(string: "0.01")!, rateDate: date, source: .ecb))
        #expect(foreign.isRatePending == false, "the snapshot must land for the test to mean anything")
        let fill = Self.fill(date: date, odometer: 118_000, litres: 26.05, isFull: true,
                             unitPrice: Decimal(string: "1.919")!, money: foreign)
        let stats = HomeStats(vehicle: Self.vehicle(homeCurrency: .rub),
                              entries: [fill], asOf: Self.asOf)

        let expected = UnitPriceFigure(amount: Decimal(string: "191.9")!, currency: .rub)
        #expect(stats.lastUnitPrice == expected)
    }

    /// The monthSpend-shaped pending treatment: a rate-pending fill is skipped
    /// (it has no home figure), so the tile keeps showing the most recent price
    /// that IS expressible in home currency - exactly as `monthSpend` keeps
    /// summing the entries whose home amount exists.
    @Test func newestPendingForeignFillFallsBackToMostRecentHomePrice() {
        let olderHome = Self.fill(date: Self.asOf - 10 * Self.day, odometer: 118_000,
                                  litres: 40, isFull: true,
                                  unitPrice: Decimal(string: "58.4")!,
                                  money: Money(amount: Decimal(string: "2336")!,
                                               currency: .rub, homeCurrency: .rub))
        let pendingEUR = Money(amount: Decimal(string: "51.81")!, currency: .eur, homeCurrency: .rub)
        let newestPending = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 119_600,
                                      litres: 27, isFull: true,
                                      unitPrice: Decimal(string: "1.919")!,
                                      money: pendingEUR)
        let stats = HomeStats(vehicle: Self.vehicle(homeCurrency: .rub),
                              entries: [olderHome, newestPending], asOf: Self.asOf)

        let expected = UnitPriceFigure(amount: Decimal(string: "58.4")!, currency: .rub)
        #expect(stats.lastUnitPrice == expected,
                "the pending foreign fill contributes no figure; the last home price stands")
    }
}
