import Foundation

/// One point of a Trends sparkline series. Derived in TankbookCore so the UI
/// does no arithmetic of its own (hard rule 2): the view only draws what it is
/// given, and a point exists only when the underlying figure is real.
public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Everything the Trends tile grid renders, derived once from the vehicle and
/// its entries and handed to the view unchanged (hard rule 2: stats are
/// derived, never stored - this is the derivation, recomputed on any entry
/// change).
///
/// It REUSES `HomeStats` for every figure Home also shows - the headline, the
/// all-in cost/km, the month spend and the last price per litre - so the two
/// screens can never disagree about a number or its label. This type only adds
/// what Home does not need: the sparkline series and the honest per-tile spans.
/// A tile whose figure is unavailable is ABSENT (nil / empty), never zero -
/// "N/A", "–" and "0.0" are not in the vocabulary (docs/ERRORS.md -> Trends).
public struct TrendsStats: Equatable, Sendable {
    public let vehicle: Vehicle
    public let home: HomeStats
    /// Consumption series: each segment's per100 by close date - the same
    /// segments the headline is built from, so the sparkline and the honest
    /// label describe the same history.
    public let consumptionSeries: [TrendPoint]
    /// The direction the consumption series is moving (lower is better),
    /// derived from the series itself - never stored (hard rule 2). `nil`
    /// below two points or on a flat series.
    public let consumptionTrend: TrendDirection?
    /// All-in cost/km per calendar month (Σ homeAmount / odometer span within
    /// the month). A month without a km span is omitted, never drawn as zero.
    public let costSeries: [TrendPoint]
    /// The direction the cost/km series is moving (lower is better). `nil`
    /// below two points or on a flat series.
    public let costTrend: TrendDirection?
    /// Total spend per calendar month (all entry types), trailing 12 months.
    public let spendSeries: [TrendPoint]
    /// Unit price per fill by date, most recent 12 fills.
    public let priceSeries: [TrendPoint]
    /// The honest span of the cost/km figure in months: the time its km span
    /// actually covers, never the full window when the data is younger
    /// (the same honesty rule as the headline's label).
    public let costPerKmSpanMonths: Int?
    /// Entries still waiting on a rate - the F9 "N entries pending rates"
    /// footnote count. Delegated to `HomeStats`, which computes it from the
    /// same counting entries (docs/JOURNEYS.md F9).
    public let pendingRateCount: Int

    public init(vehicle: Vehicle, entries: [any Entry],
                asOf: Date = Date(), calendar: Calendar = .current,
                duplicateResolutions: Set<DuplicateDetector.PairKey> = []) {
        self.vehicle = vehicle
        self.home = HomeStats(vehicle: vehicle, entries: entries, asOf: asOf,
                              calendar: calendar, duplicateResolutions: duplicateResolutions)
        self.pendingRateCount = home.pendingRateCount

        // The S2 single-count invariant, exactly as HomeStats applies it: only
        // the counting member of an unresolved duplicate pair feeds the series,
        // so a duplicate never double-counts a sparkline either.
        let fills = entries.compactMap { $0 as? FillUp }
        let pairs = DuplicateDetector.pairs(in: fills, resolved: duplicateResolutions)
        let excludedIDs = Set(pairs.map(\.excludedID))
        let countingEntries = entries.filter { !excludedIDs.contains($0.id) }
        let countingFills = fills.filter { !excludedIDs.contains($0.id) }

        let charges = entries.compactMap { $0 as? ChargeSession }
        let fuelSegments = ConsumptionEngine.segments(for: countingFills, tankCapacityL: vehicle.tankCapacityL)
        let evSegments = ConsumptionEngine.evSegments(for: charges)
        let usesEV = vehicle.powertrain == .ev || !evSegments.isEmpty
        let segments = usesEV ? evSegments : fuelSegments

        self.consumptionSeries = segments
            .sorted { $0.closes < $1.closes }
            .map { TrendPoint(date: $0.closes, value: $0.per100) }
        self.consumptionTrend = TrendDirection.lowerIsBetter(consumptionSeries.map(\.value))

        self.costSeries = Self.monthlyCostSeries(entries: countingEntries, calendar: calendar, asOf: asOf)
        self.costTrend = TrendDirection.lowerIsBetter(costSeries.map(\.value))
        self.spendSeries = Self.monthlySpendSeries(entries: countingEntries, calendar: calendar, asOf: asOf)
        self.priceSeries = Self.priceSeries(entries: countingEntries)
        self.costPerKmSpanMonths = Self.costPerKmSpanMonths(entries: countingEntries, asOf: asOf)
    }

    // MARK: - Series derivation (all on top of the engine)

    /// The start of the calendar month containing `date`.
    private static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private static func trailingTwelveMonthsStart(asOf: Date, calendar: Calendar) -> Date {
        guard let start = calendar.date(byAdding: .month, value: -11, to: asOf) else { return asOf }
        return monthStart(start, calendar: calendar)
    }

    private static func monthlySpendSeries(entries: [any Entry], calendar: Calendar,
                                           asOf: Date) -> [TrendPoint] {
        let cutoff = trailingTwelveMonthsStart(asOf: asOf, calendar: calendar)
        let grouped = Dictionary(grouping: entries) { monthStart($0.date, calendar: calendar) }
        return grouped
            .filter { $0.key >= cutoff }
            .map { monthStart, monthEntries -> TrendPoint in
                let total = monthEntries.reduce(Decimal.zero) { partial, entry in
                    guard let amount = entry.money?.homeAmount else { return partial }
                    return partial + amount
                }
                return TrendPoint(date: monthStart, value: (total as NSDecimalNumber).doubleValue)
            }
            .sorted { $0.date < $1.date }
    }

    private static func monthlyCostSeries(entries: [any Entry], calendar: Calendar,
                                          asOf: Date) -> [TrendPoint] {
        let cutoff = trailingTwelveMonthsStart(asOf: asOf, calendar: calendar)
        let grouped = Dictionary(grouping: entries) { monthStart($0.date, calendar: calendar) }
        return grouped
            .filter { $0.key >= cutoff }
            .compactMap { monthStart, monthEntries -> TrendPoint? in
                let total = monthEntries.reduce(Decimal.zero) { partial, entry in
                    guard let amount = entry.money?.homeAmount else { return partial }
                    return partial + amount
                }
                let odometers = monthEntries.compactMap(\.odometer)
                guard let maxOdo = odometers.max(), let minOdo = odometers.min(),
                      maxOdo > minOdo else { return nil }
                let km = Double(maxOdo - minOdo)
                return TrendPoint(date: monthStart, value: (total as NSDecimalNumber).doubleValue / km)
            }
            .sorted { $0.date < $1.date }
    }

    private static func priceSeries(entries: [any Entry]) -> [TrendPoint] {
        let prices = entries
            .compactMap { entry -> TrendPoint? in
                if let fill = entry as? FillUp, let price = fill.unitPrice {
                    return TrendPoint(date: fill.date, value: (price as NSDecimalNumber).doubleValue)
                }
                if let charge = entry as? ChargeSession, let price = charge.unitPrice {
                    return TrendPoint(date: charge.date, value: (price as NSDecimalNumber).doubleValue)
                }
                return nil
            }
            .sorted { $0.date < $1.date }
        return Array(prices.suffix(12))
    }

    private static func costPerKmSpanMonths(entries: [any Entry], asOf: Date) -> Int? {
        let start = asOf.addingTimeInterval(-Double(90) * 86_400)
        let withOdometer = entries.filter { $0.date >= start && $0.date <= asOf && $0.odometer != nil }
        let odometers = withOdometer.compactMap(\.odometer)
        // No km span -> the cost/km figure itself is nil, so its span label
        // has nothing to describe either.
        guard let maxOdo = odometers.max(), let minOdo = odometers.min(),
              maxOdo > minOdo,
              let earliest = withOdometer.map(\.date).min() else { return nil }
        let days = asOf.timeIntervalSince(earliest) / 86_400
        let months = max(1, Int((days / 30).rounded()))
        return min(3, months)
    }
}
