import Foundation

/// A per-unit price ready to render (RV.29): the amount already expressed in
/// `currency`, and `currency` the symbol to print beside it.
///
/// Before this type existed the last-price vital was a bare `Decimal`, and Home
/// stamped the *vehicle's* home symbol on it. But a fill's `unitPrice` is
/// stored in the currency it was paid in (docs/SCHEMA.md, FillUp - "per liter,
/// original currency"), so a foreign fill on a home-currency car rendered its
/// EUR number under a RUB symbol - the money pair at its most direct lie (hard
/// rule 3). Carrying the currency makes the mismatch impossible to render.
public struct UnitPriceFigure: Equatable, Sendable {
    /// The per-unit price, denominated in `currency`.
    public let amount: Decimal
    /// The currency `amount` is in - the symbol the renderer must print beside it.
    public let currency: CurrencyCode

    public init(amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }
}

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
    /// The most recent fill's price per unit in the currency the vehicle's
    /// money figures are kept in (the fill's money-pair home side - hard rule 3),
    /// NOT the raw original a bare `Decimal` used to smuggle out (RV.29).
    ///
    /// A foreign fill converts with its OWN immutable rate snapshot, so this
    /// figure never shifts when rates move. A fill still waiting on a rate has
    /// no home figure yet and is skipped exactly as `monthSpend` skips it
    /// (docs/ERRORS.md -> Home, F9) - the tile then shows the most recent price
    /// that IS expressible in home currency. `nil` when no counting entry has a
    /// unit price expressible in home currency at all.
    public let lastUnitPrice: UnitPriceFigure?
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
        self.lastUnitPrice = Self.lastUnitPrice(entries: countingEntries,
                                                 vehicleHome: vehicle.homeCurrency)
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

    // MARK: - The unit-price figure (RV.29)

    /// The unit price of every counting entry that has one, oldest first, each
    /// expressed in the currency of its money pair's home side (see
    /// `unitPriceFigure`). Home takes the last of this list for its vital;
    /// Trends plots the whole list as its price sparkline. ONE derivation, so
    /// the tile's figure is always the series' final point and the two screens
    /// can never disagree (hard rule 2 - derived in core, never in the view).
    static func unitPriceHistory(entries: [any Entry],
                                 vehicleHome: CurrencyCode) -> [(date: Date, price: UnitPriceFigure)] {
        entries
            .compactMap { entry -> (date: Date, price: UnitPriceFigure)? in
                guard let price = Self.unitPriceFigure(of: entry, vehicleHome: vehicleHome) else {
                    return nil
                }
                return (entry.date, price)
            }
            .sorted { $0.date < $1.date }
    }

    /// The per-unit price of an entry in the currency of its money pair's home
    /// side, when that figure exists.
    ///
    /// - A same-currency fill's snapshot rate is 1, so its stored price is
    ///   already home and is returned unchanged.
    /// - A foreign fill converts its stored original unit price by its OWN
    ///   immutable snapshot rate (`home = original / rate`, docs/SCHEMA.md
    ///   conversion semantics) - display-only arithmetic, nothing is written.
    /// - A foreign fill whose rate is still pending has no home figure: `nil`,
    ///   the same honesty `monthSpend` applies when it skips a pending entry
    ///   (docs/ERRORS.md -> Home, F9). Rendering a *converted* value that does
    ///   not exist is not an option (RV.29 decision - see HomeVitalsRow).
    /// - An entry with no money pair at all (a tariff-priced home charge) has
    ///   no rate because none is needed: its unit price is already in the
    ///   vehicle's home currency.
    static func unitPriceFigure(of entry: any Entry,
                                vehicleHome: CurrencyCode) -> UnitPriceFigure? {
        let price: Decimal?
        if let fill = entry as? FillUp {
            price = fill.unitPrice
        } else if let charge = entry as? ChargeSession {
            price = charge.unitPrice
        } else {
            return nil
        }
        guard let price else { return nil }

        guard let money = entry.money else {
            // No money pair, no rate: the price is home already.
            return UnitPriceFigure(amount: price, currency: vehicleHome)
        }
        guard let rate = money.rate, rate > 0 else { return nil }
        return UnitPriceFigure(amount: price / rate, currency: money.homeCurrency)
    }

    private static func lastUnitPrice(entries: [any Entry],
                                      vehicleHome: CurrencyCode) -> UnitPriceFigure? {
        unitPriceHistory(entries: entries, vehicleHome: vehicleHome).last?.price
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
