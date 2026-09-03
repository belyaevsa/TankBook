import Testing
import Foundation
@testable import TankbookCore

/// P1.10: the honest-label rule (docs/SCHEMA.md -> HEADLINE) and the Trends
/// derivation on top of it. The wording is the feature: a number computed over
/// five months labelled as three is a lie the user cannot detect, so the label
/// must report the REAL span, and a first estimate must say it is provisional.
/// TrendsStats reuses HomeStats for every shared figure, so Home and Trends can
/// never disagree about a number or its label.
struct TrendsLabelTests {

    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.asOf - 200 * Self.day, updatedAt: Self.asOf - 200 * Self.day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(date: Date, odometer: Int, litres: Double, isFull: Bool = true,
                             conflict: ConflictState = .none,
                             amount: Decimal = Decimal(string: "50")!) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Money(amount: amount, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: conflict,
            purchaseGroupId: nil, volumeL: litres, unitPrice: Decimal(string: "1.5"),
            fuelKind: .petrol95, fuelGrade: nil, isFull: isFull,
            tankLevelAfterPct: isFull ? 100 : nil, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    // MARK: - The three label cases (the deliverable)

    @Test func enoughSegmentsInWindowYieldLastThreeMonths() {
        let f1 = Self.fill(date: Self.asOf - 40 * Self.day, odometer: 118_000, litres: 41)
        let f2 = Self.fill(date: Self.asOf - 35 * Self.day, odometer: 118_300, litres: 42)
        let f3 = Self.fill(date: Self.asOf - 16 * Self.day, odometer: 118_800, litres: 40)
        let f4 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 119_300, litres: 43)
        let f5 = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 119_800, litres: 42)

        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2, f3, f4, f5], asOf: Self.asOf)
        #expect(stats.home.headline?.label == .window(months: 3))
        #expect(stats.home.headline?.label.honestText() == "last 3 months")
    }

    @Test func extendedWindowLabelReportsTheActualSpanNotTheClaimedWindow() {
        // D3-shaped (docs/fixtures/consumption-golden.json): segments close 140,
        // 75 and 10 days ago - only two inside 90 days, so the floor of 3 pulls
        // the window back to the REAL ~140-day span.
        let f1 = Self.fill(date: Self.asOf - 190 * Self.day, odometer: 118_000, litres: 47)
        let f2 = Self.fill(date: Self.asOf - 140 * Self.day, odometer: 118_690, litres: 48.5)
        let f3 = Self.fill(date: Self.asOf - 75 * Self.day, odometer: 119_340, litres: 45)
        let f4 = Self.fill(date: Self.asOf - 10 * Self.day, odometer: 119_980, litres: 44.5)

        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2, f3, f4], asOf: Self.asOf)
        let headline = stats.home.headline
        #expect(headline?.windowExtended == true)
        #expect(headline?.label == .window(months: 5))
        #expect(headline?.label.honestText() == "last 5 months")
        // The lie the rule exists to prevent:
        #expect(headline?.label.honestText() != "last 3 months")
    }

    @Test func belowFloorLabelIsFirstEstimateWithCorrectSingularAndPlural() {
        // Two full tanks close exactly one segment: below the floor.
        let f1 = Self.fill(date: Self.asOf - 16 * Self.day, odometer: 118_000, litres: 42)
        let f2 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_800, litres: 40)
        let one = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2], asOf: Self.asOf)
        #expect(one.home.headline?.label == .firstEstimate(cycles: 1))
        #expect(one.home.headline?.label.honestText() == "first estimate · 1 fill cycle")

        // Three full tanks close two segments: still below the floor, plural form.
        let f3 = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 119_600, litres: 43)
        let two = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2, f3], asOf: Self.asOf)
        #expect(two.home.headline?.label == .firstEstimate(cycles: 2))
        #expect(two.home.headline?.label.honestText() == "first estimate · 2 fill cycles")
    }

    // MARK: - The honest span is not decoration

    @Test func windowLabelOfOneMonthIsSingular() {
        #expect(Headline.Label.window(months: 1).honestText() == "last month")
    }

    // MARK: - Distance-weighted (not mean of per100s)

    @Test func headlineIsDistanceWeightedNotTheMeanOfPer100s() {
        // Short segment, high consumption; long segment, low consumption - the
        // two differ, and the headline must be the weighted value.
        let f1 = Self.fill(date: Self.asOf - 10 * Self.day, odometer: 118_000, litres: 40)
        let f2 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_100, litres: 40)   // 100 km, 40 L
        let f3 = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 119_100, litres: 10)   // 1,000 km, 10 L
        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2, f3], asOf: Self.asOf)

        let weighted = (40.0 + 10.0) / (100.0 + 1_000.0) * 100 // 4.545...
        let arithmeticMean = (40.0 + 1.0) / 2                    // 20.5
        #expect(stats.home.headline != nil)
        #expect(abs((stats.home.headline?.value ?? 0) - weighted) < 0.01)
        #expect(abs((stats.home.headline?.value ?? 0) - arithmeticMean) > 1.0)
    }

    // MARK: - Cost/km is all-in (docs/SCHEMA.md -> COST/KM)

    @Test func costPerKmMovesWhenAServiceRecordIsAdded() {
        let f1 = Self.fill(date: Self.asOf - 30 * Self.day, odometer: 118_000, litres: 40,
                           amount: Decimal(string: "50")!)
        let f2 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_800, litres: 41,
                           amount: Decimal(string: "60")!)
        let fuelOnly = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2], asOf: Self.asOf).home.costPerKm
        // 110 EUR over the 800 km window span.
        #expect(abs((fuelOnly ?? 0) - 110.0 / 800.0) < 0.0001)

        let service = ServiceRecord(
            id: UUID.v7(), createdAt: Self.asOf, updatedAt: Self.asOf, deletedAt: nil,
            vehicleId: UUID.v7(), date: Self.asOf - 2 * Self.day, odometer: 118_700,
            money: Money(amount: Decimal(string: "148")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Garage", items: [], usedParts: [],
            tireSetId: nil, proposedReminderId: nil)

        let withService = TrendsStats(vehicle: Self.vehicle(),
                                      entries: [f1, f2, service], asOf: Self.asOf).home.costPerKm
        #expect(abs((withService ?? 0) - (110.0 + 148.0) / 800.0) < 0.0001,
                "a service record must move the all-in cost/km")
        #expect(withService != fuelOnly)
    }

    // MARK: - Excluded count is the engine's, exactly

    @Test func excludedCountMatchesEngineFlagsExactlyIncludingZero() {
        let empty = TrendsStats(vehicle: Self.vehicle(), entries: [], asOf: Self.asOf)
        #expect(empty.home.excludedEntryCount == 0)
        #expect(empty.home.excludedEntryIDs.isEmpty)

        let clean = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_800, litres: 40)
        let flagged = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 119_600, litres: 42,
                                conflict: .flagged(kind: .order, detectedAt: Self.asOf))
        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [clean, flagged], asOf: Self.asOf)
        #expect(stats.home.excludedEntryCount == 1)
        #expect(stats.home.excludedEntryIDs == [flagged.id],
                "the footnote must know WHICH entry to route to")
    }

    // MARK: - Tiles omit rather than fabricate

    @Test func tilesOmitRatherThanFabricateWhenNothingIsHonest() {
        let empty = TrendsStats(vehicle: Self.vehicle(), entries: [], asOf: Self.asOf)
        #expect(empty.home.headline == nil)
        #expect(empty.home.costPerKm == nil)
        #expect(empty.home.monthSpend == nil)
        #expect(empty.home.lastUnitPrice == nil)
        #expect(empty.consumptionSeries.isEmpty)
        #expect(empty.costSeries.isEmpty)
        #expect(empty.spendSeries.isEmpty)
        #expect(empty.priceSeries.isEmpty)
        #expect(empty.costPerKmSpanMonths == nil)
    }

    @Test func singleFillShowsOnlyTheTilesThatHaveHonestData() {
        // D4-shaped: one full tank, no closed segment, one odometer reading.
        // Consumption and cost/km have nothing honest; month spend and the last
        // price do.
        let single = Self.fill(date: Self.asOf - 6 * Self.day, odometer: 118_000, litres: 42)
        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [single], asOf: Self.asOf)
        #expect(stats.home.headline == nil)
        #expect(stats.home.costPerKm == nil)
        #expect(stats.home.monthSpend != nil)
        #expect(stats.home.lastUnitPrice != nil)
        #expect(stats.costPerKmSpanMonths == nil)
    }

    // MARK: - The shared-label guarantee (Home and Trends, one rule)

    @Test func trendsConsumptionLabelMatchesHomeHeadlineLabel() {
        let f1 = Self.fill(date: Self.asOf - 16 * Self.day, odometer: 118_000, litres: 42)
        let f2 = Self.fill(date: Self.asOf - 5 * Self.day, odometer: 118_800, litres: 40)
        let f3 = Self.fill(date: Self.asOf - 1 * Self.day, odometer: 119_600, litres: 43)
        let entries: [any Entry] = [f1, f2, f3]
        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries, asOf: Self.asOf)
        let home = HomeStats(vehicle: Self.vehicle(), entries: entries, asOf: Self.asOf)

        #expect(trends.home.headline == home.headline)
        #expect(trends.home.headline?.label.honestText() == home.headline?.label.honestText())
    }

    // MARK: - RV.29: the price sparkline is home-denominated too

    private static func pricedFill(_ date: Date, litres: Double, odometer: Int,
                                   unitPrice: Decimal, money: Money) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, volumeL: litres,
            unitPrice: unitPrice, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    /// The Trends half of RV.29: a sparkline must plot one currency, so a
    /// foreign fill lands at its CONVERTED home value (its own snapshot rate),
    /// never at its raw original number among home figures. A rate-pending fill
    /// has no home figure and is absent from the series - the same exclusion as
    /// Home's vital, so the series' final point is always the tile's figure.
    @Test func priceSeriesConvertsForeignFillsAndSkipsPendingOnes() {
        let plnHome = Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .eur)
        let f1 = Self.pricedFill(Self.asOf - 10 * Self.day, litres: 40, odometer: 118_000,
                                 unitPrice: Decimal(string: "1.5")!, money: plnHome)
        // A PLN fill converted at its own snapshot rate (4.5 PLN/EUR): 6.75 PLN/L
        // is 1.50 EUR/L. Plotting the raw 6.75 among ~1.5 figures is the RV.29 lie.
        let convertedDate = Self.asOf - 5 * Self.day
        let foreign = Money(amount: Decimal(string: "60")!, currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: Decimal(string: "4.5")!, rateDate: convertedDate, source: .ecb))
        let f2 = Self.pricedFill(convertedDate, litres: 40, odometer: 118_800,
                                 unitPrice: Decimal(string: "6.75")!, money: foreign)
        // The newest fill is rate-pending: it must be ABSENT, not plotted raw.
        let pending = Money(amount: Decimal(string: "289.50")!, currency: .pln, homeCurrency: .eur)
        let f3 = Self.pricedFill(Self.asOf - 1 * Self.day, litres: 47.3, odometer: 119_600,
                                 unitPrice: Decimal(string: "6.120")!, money: pending)

        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2, f3], asOf: Self.asOf)

        #expect(stats.priceSeries.count == 2)
        #expect(abs((stats.priceSeries[0].value) - 1.5) < 0.0001)
        #expect(abs((stats.priceSeries[1].value) - 1.5) < 0.0001,
                "6.75 PLN/L must be plotted at its converted 1.50 EUR/L, never raw (RV.29)")
        #expect(stats.home.lastUnitPrice == UnitPriceFigure(amount: Decimal(string: "1.5")!,
                                                           currency: .eur),
                "the tile's figure must be the series' final point")
    }

    @Test func costPerKmSpanReportsTheRealDataSpanNotTheWindow() {
        // Two weeks of odometer data: the honest label is "last month", never
        // the full 90-day window.
        let f1 = Self.fill(date: Self.asOf - 12 * Self.day, odometer: 118_000, litres: 40)
        let f2 = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 118_800, litres: 41)
        let stats = TrendsStats(vehicle: Self.vehicle(), entries: [f1, f2], asOf: Self.asOf)
        #expect(stats.costPerKmSpanMonths == 1)
    }
}
