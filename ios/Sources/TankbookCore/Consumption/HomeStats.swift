import Foundation

/// Everything Home renders, computed once from the vehicle and its entries and
/// handed to the view unchanged (hard rule 2: stats are derived, never stored -
/// this is the derivation, recomputed on any entry change). All figures come
/// from `ConsumptionEngine`; this type adds no arithmetic of its own.
///
/// The rule that keeps it honest: a vital that has nothing to show is `nil`,
/// never zero. Home omits a tile whose value is `nil` - "N/A", "–" and "0.0"
/// are not in the vocabulary (docs/ERRORS.md -> Home, and the L4 no-N/A-tiles
/// assertion). With zero entries every data-hungry vital is absent, not zero.
public struct HomeStats: Equatable, Sendable {
    public let vehicle: Vehicle
    /// Headline consumption over the trailing window/floor. `nil` until a
    /// segment closes - a single full tank opens one but does not close it.
    public let headline: Headline?
    /// The direction the headline's per100 series is moving, derived from the
    /// same segments the headline is built from (hard rule 2 - never stored).
    /// `nil` with fewer than two closing segments or a flat series: VoiceOver
    /// then announces the figure with no invented "improving"/"worsening"
    /// (docs/DESIGN.md -> Accessibility floor).
    public let headlineTrend: TrendDirection?
    /// All-history distance-weighted consumption; `nil` with no usable distance.
    public let lifetime: Double?
    /// All-in cost per km over the window; `nil` with no km span in the window.
    public let costPerKm: Double?
    /// Sum of home-currency spend in the calendar month containing `asOf`.
    public let monthSpend: Decimal?
    /// The most recent fill's price per unit; `nil` with no fill.
    public let lastUnitPrice: Decimal?
    /// Best (lowest) per100 among segments closing in the calendar year of
    /// `asOf` - the artboard's "Best this year".
    public let bestThisYear: Double?
    /// The car's current odometer: the latest entry odometer, else the vehicle's
    /// `initialOdometer` (real baseline data, never fabricated).
    public let odometer: Int?
    /// Date of the most recent entry ("updated <date>"); `nil` when there are
    /// no entries (the view falls back to "added" on `vehicle.createdAt`).
    public let updatedAt: Date?
    /// Conflict-flagged entries plus the excluded members of unresolved S2
    /// duplicate pairs - the "N entries excluded" footnote count. Derived from
    /// the validation/duplicate engines' flags, never hard-coded
    /// (docs/ERRORS.md -> Home, rows F9a and S2).
    public let excludedEntryCount: Int
    /// The excluded entries' IDs, most recent first - the footnote's "tap -> the
    /// flagged entry" next step needs a concrete target (hard rule 7).
    public let excludedEntryIDs: [UUID]
    /// Entries still waiting on a rate among the counting entries - the F9
    /// "N entries pending rates" footnote count (docs/JOURNEYS.md F9). Derived,
    /// never stored (hard rule 2); `money == nil` (a free event) is not pending.
    public let pendingRateCount: Int
    /// True once a headline exists but is a first estimate (fewer segments than
    /// the floor, nothing older to extend into).
    public let isFirstEstimate: Bool
    /// The D4 state: at least one full tank logged but no segment closed yet -
    /// "One more full tank and your consumption appears".
    public let needsAnotherFullTank: Bool
    /// True when at least one entry exists at all.
    public let hasEntries: Bool

    public init(vehicle: Vehicle, entries: [any Entry],
                asOf: Date = Date(), calendar: Calendar = .current,
                duplicateResolutions: Set<DuplicateDetector.PairKey> = []) {
        self.vehicle = vehicle

        // The S2 single-count invariant (docs/SYNC.md S2): until the user
        // decides, only ONE entry of an unresolved duplicate pair counts in
        // consumption, month totals and every derived figure - stats never
        // double. The counted entry is chosen deterministically (see
        // DuplicateDetector.counted); the excluded member is set aside here and
        // never reaches the engine or the totals.
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

        self.headline = ConsumptionEngine.headline(segments: segments, asOf: asOf)
        self.headlineTrend = TrendDirection.lowerIsBetter(
            segments.sorted { $0.closes < $1.closes }.map(\.per100))
        self.lifetime = ConsumptionEngine.lifetime(segments: segments)
        self.costPerKm = ConsumptionEngine.costPerKm(entries: countingEntries, asOf: asOf)
        self.monthSpend = Self.monthSpend(entries: countingEntries, asOf: asOf, calendar: calendar)
        self.lastUnitPrice = Self.lastUnitPrice(entries: countingEntries)
        self.bestThisYear = Self.bestThisYear(segments: segments, asOf: asOf, calendar: calendar)

        self.odometer = countingEntries.compactMap(\.odometer).max() ?? vehicle.initialOdometer
        self.updatedAt = countingEntries.compactMap(\.date).max()
        var excluded: Set<UUID> = excludedIDs
        for entry in entries where entry.conflict != .none {
            excluded.insert(entry.id)
        }
        self.excludedEntryCount = excluded.count
        self.excludedEntryIDs = entries
            .filter { excluded.contains($0.id) }
            .sorted { $0.date > $1.date }
            .map(\.id)
        self.pendingRateCount = countingEntries
            .filter { $0.money?.isRatePending == true }
            .count
        if case .firstEstimate = headline?.label {
            self.isFirstEstimate = true
        } else {
            self.isFirstEstimate = false
        }
        self.needsAnotherFullTank = countingFills.contains(where: { $0.isFull }) && headline == nil
        self.hasEntries = !entries.isEmpty
    }

    // MARK: - Private derivation (all on top of the engine)

    private static func monthSpend(entries: [any Entry], asOf: Date,
                                   calendar: Calendar) -> Decimal? {
        guard let month = calendar.dateInterval(of: .month, for: asOf) else { return nil }
        let inMonth = entries.filter { month.contains($0.date) }
        guard !inMonth.isEmpty else { return nil }
        return inMonth.reduce(Decimal.zero) { partial, entry in
            guard let homeAmount = entry.money?.homeAmount else { return partial }
            return partial + homeAmount
        }
    }

    private static func lastUnitPrice(entries: [any Entry]) -> Decimal? {
        entries
            .compactMap { entry -> (date: Date, price: Decimal)? in
                if let fill = entry as? FillUp, let price = fill.unitPrice {
                    return (fill.date, price)
                }
                if let charge = entry as? ChargeSession, let price = charge.unitPrice {
                    return (charge.date, price)
                }
                return nil
            }
            .max { $0.date < $1.date }?
            .price
    }

    private static func bestThisYear(segments: [Segment], asOf: Date,
                                     calendar: Calendar) -> Double? {
        guard let year = calendar.dateInterval(of: .year, for: asOf) else { return nil }
        return segments
            .filter { year.contains($0.closes) }
            .map(\.per100)
            .min()
    }
}
