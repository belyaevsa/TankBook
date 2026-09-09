import Foundation

/// The fuelKind families a segment may span. A segment only merges fills of the
/// same family - electricity never mixes with combustion (docs/SCHEMA.md, SEGMENT
/// "same fuelKind family").
private enum FuelFamily: Hashable {
    case combustion
    case electric
}

extension FuelKind {
    fileprivate var family: FuelFamily {
        switch self {
        case .electricity: return .electric
        default: return .combustion
        }
    }
}

/// The Home headline stat: distance-weighted consumption over the selected
/// segments, with the honest span label (docs/SCHEMA.md, Derived: consumption
/// -> HEADLINE).
public struct Headline: Equatable, Sendable {
    /// L/100km over the selected segments: Σ litres / Σ km x 100. As displayed,
    /// rounded to 1 decimal place.
    public let value: Double
    /// Number of segments feeding the headline.
    public let segmentCount: Int
    /// The span the headline claims: the window, or the REAL span when the
    /// window had to extend or the data is a first estimate.
    public let spanDays: Int
    /// True when the floor forced the window to reach older segments.
    public let windowExtended: Bool
    public let totalLitres: Double
    public let totalKm: Double
    /// Honest label: "last N months" over the real span, or a first estimate
    /// when there are fewer segments than the floor.
    public let label: Label

    public enum Label: Equatable, Sendable {
        case window(months: Int)
        case firstEstimate(cycles: Int)
    }

    public init(value: Double, segmentCount: Int, spanDays: Int, windowExtended: Bool,
                totalLitres: Double, totalKm: Double, label: Label) {
        self.value = value
        self.segmentCount = segmentCount
        self.spanDays = spanDays
        self.windowExtended = windowExtended
        self.totalLitres = totalLitres
        self.totalKm = totalKm
        self.label = label
    }
}

// MARK: - Honest label text

extension Headline.Label {
    /// The honest label in the default language (English), per docs/SCHEMA.md
    /// -> HEADLINE. The span a number is actually made of: "last 3 months"
    /// when the window is satisfied; the REAL span when the window had to
    /// extend ("last 5 months", never "last 3 months"); "first estimate · N
    /// fill cycles" below the floor with nothing to extend into. The wording
    /// is the feature - a number computed over five months labelled as three
    /// is a lie the user cannot detect, so the label reports the real span.
    /// Home and Trends render this same rule through the app's String Catalog
    /// (EN + RU); this is the canonical text the catalog keys and the L1 tests
    /// pin.
    public func honestText() -> String {
        switch self {
        case .window(let months):
            return months == 1 ? "last month" : "last \(months) months"
        case .firstEstimate(let cycles):
            return cycles == 1 ? "first estimate · 1 fill cycle" : "first estimate · \(cycles) fill cycles"
        }
    }
}

/// The all-in cost-per-km figure over a window (docs/SCHEMA.md, Derived:
/// consumption -> COST/KM), as an EXACT statement only: `amount` is the full,
/// converted home sum over the window in `currency`, and the figure exists
/// solely when no money-bearing row in the window is still rate-pending and the
/// known figures share one home currency (RV.147). `nil` in its place means the
/// window cannot state a figure - the tile is omitted, never a plausible
/// understatement. Carrying the amount and its currency together means a
/// renderer cannot pair the figure with a foreign symbol (the RV.145 rule, now
/// applied to the ratio).
public struct CostPerKmFigure: Equatable, Sendable {
    /// The exact Σ homeAmount the ratio is built on, in `currency`.
    public let amount: Decimal
    /// The currency `amount` is denominated in - the marker to print beside it.
    public let currency: CurrencyCode
    /// The odometer span dividing `amount` (the ratio's known denominator).
    public let km: Double
    /// The ratio as displayed: `amount / km`. Money stays Decimal in `amount`;
    /// the Double is the final rendered rate, computed exactly as before.
    public var perKm: Double {
        (amount as NSDecimalNumber).doubleValue / km
    }

    public init(amount: Decimal, currency: CurrencyCode, km: Double) {
        self.amount = amount
        self.currency = currency
        self.km = km
    }
}

/// Pure consumption math (docs/SCHEMA.md, Derived: consumption). All functions
/// are stateless: derived values are computed on demand and NEVER cached or
/// stored. Any change to any FillUp of a vehicle triggers a full recompute via
/// `recompute` (docs/SCHEMA.md, Recalculation on edit) - this engine is that
/// recompute, made explicit and correct-by-construction.
public enum ConsumptionEngine {

    // MARK: Segments

    /// The vehicle's segment list, derived from its full fill history.
    ///
    /// A segment spans consecutive `isFull` fills of the same fuelKind family:
    /// `km` = odo(close) - odo(open); `litres` = sum of every fill AFTER the
    /// opening full fill, up to and INCLUDING the closing one; `per100` =
    /// litres / km x 100. A segment touching an unresolved `ConflictState`
    /// (opening, closing, or any fill in between) is excluded.
    ///
    /// TANK-LEVEL (v1.x refinement, gated on `tankCapacityL` being set): when a
    /// non-full fill carries `tankLevelAfterPct` it may close a segment using
    /// `litres_adjusted = Σ volume + (levelOpen - levelClose)/100 x capacity`.
    /// Without a capacity the engine falls back to full-to-full segments.
    public static func segments(for fills: [FillUp], tankCapacityL: Double? = nil) -> [Segment] {
        let sorted = fills.sorted(by: fillOrder)
        var result: [Segment] = []
        var seen = Set<FuelFamily>()
        for fill in sorted where !seen.contains(fill.fuelKind.family) {
            seen.insert(fill.fuelKind.family)
            let familyFills = sorted.filter { $0.fuelKind.family == fill.fuelKind.family }
            result.append(contentsOf: segments(in: familyFills, tankCapacityL: tankCapacityL))
        }
        return result
    }

    /// The recompute entry point called on every save / sync-merge batch
    /// (docs/SCHEMA.md, Recalculation on edit). A pure linear pass; nothing is
    /// cached. Same result as `segments(for:tankCapacityL:)` - this name is the
    /// contract callers use on any FillUp change.
    public static func recompute(fills: [FillUp], tankCapacityL: Double? = nil) -> [Segment] {
        segments(for: fills, tankCapacityL: tankCapacityL)
    }

    // MARK: Headline

    /// The Home screen headline: distance-weighted consumption over the trailing
    /// `windowDays`, extended to the `floor` most recent segments when the window
    /// alone yields fewer (docs/SCHEMA.md, Derived: consumption -> HEADLINE).
    ///
    /// `value` is `Σ litres / Σ km x 100` over the selected segments - explicitly
    /// NOT the arithmetic mean of their per100 values. `label` reports the honest
    /// span ("last N months") or, below the floor with nothing to extend into, a
    /// first estimate over the available fill cycles.
    public static func headline(segments: [Segment], asOf: Date,
                                windowDays: Int = 90, floor: Int = 3) -> Headline? {
        let windowStart = asOf.addingTimeInterval(-Double(windowDays) * 86400)
        let newestFirst = segments.sorted { $0.closes > $1.closes }
        let inWindow = newestFirst.filter { $0.closes >= windowStart && $0.closes <= asOf }

        let selected: [Segment]
        if inWindow.count >= floor {
            selected = inWindow
        } else {
            selected = Array(newestFirst.prefix(floor))
        }
        guard !selected.isEmpty else { return nil }

        let extended = inWindow.count < floor && selected.contains { $0.closes < windowStart }
        let earliestClose = selected.map(\.closes).min() ?? asOf
        let realSpanDays = max(0, Int((asOf.timeIntervalSince(earliestClose) / 86400).rounded()))
        // spanDays is the window length when the window alone satisfies the floor,
        // and the REAL span whenever the data is sparser than that (extended window,
        // or a first estimate with nothing older to pull in).
        let spanDays = (extended || inWindow.count < floor) ? realSpanDays : windowDays

        let totalLitres = selected.reduce(0) { $0 + $1.litres }
        let totalKm = selected.reduce(0) { $0 + $1.km }
        guard totalKm > 0 else { return nil }
        let value = totalLitres / totalKm * 100

        let label: Headline.Label
        if segments.count < floor {
            label = .firstEstimate(cycles: selected.count)
        } else {
            label = .window(months: Int((Double(spanDays) / 30).rounded()))
        }

        return Headline(
            value: value,
            segmentCount: selected.count,
            spanDays: spanDays,
            windowExtended: extended,
            totalLitres: totalLitres,
            totalKm: totalKm,
            label: label
        )
    }

    /// Secondary stat: distance-weighted consumption over ALL conflict-free
    /// segments of the vehicle's history (docs/SCHEMA.md, Derived: consumption
    /// -> LIFETIME). `nil` when there is no usable distance.
    public static func lifetime(segments: [Segment]) -> Double? {
        guard !segments.isEmpty else { return nil }
        let totalLitres = segments.reduce(0) { $0 + $1.litres }
        let totalKm = segments.reduce(0) { $0 + $1.km }
        guard totalKm > 0 else { return nil }
        return totalLitres / totalKm * 100
    }

    // MARK: Cost

    /// All-in cost per km, stated only when the window's money is EXACT
    /// (RV.147, docs/SCHEMA.md, Derived: consumption -> COST/KM).
    ///
    /// A cost-per-km is a RATIO: a partial numerator (rate-pending rows omitted)
    /// over a COMPLETE odometer denominator is low by an unknown amount while
    /// looking perfectly plausible - worse than a visibly missing number. So the
    /// figure exists only when the shared month classifier (the same accumulator
    /// the Log divider and the month tiles reduce through, RV.112/RV.145) calls
    /// the window `.complete`: every money-bearing row has converted AND the
    /// known figures share one home currency. A window holding a rate-pending
    /// row, or known figures homed in more than one currency, has NO figure -
    /// the tile is absent and the F9 footnote says why. `amount` is exact in
    /// `currency` (never the vehicle's by default - the figure carries its own
    /// marker, RV.145).
    public static func costPerKm(entries: [any Entry], windowDays: Int = 90,
                                 asOf: Date, homeCurrency: CurrencyCode) -> CostPerKmFigure? {
        let start = asOf.addingTimeInterval(-Double(windowDays) * 86400)
        let inWindow = entries.filter { $0.date >= start && $0.date <= asOf }
        var accumulator = LogStream.MonthTotal.Accumulator(vehicleHome: homeCurrency)
        accumulator.add(contentsOf: inWindow.map(\.money))
        let known: (amount: Decimal, currency: CurrencyCode)
        switch accumulator.monthTotal {
        case .complete(let amount, let currency):
            known = (amount, currency)
        case .partial, .mixed, .pending:
            // A pending row has no home amount yet, and a partial or mixed
            // window has no exact total to divide - never an understated figure.
            return nil
        }
        let odometers = inWindow.compactMap(\.odometer)
        guard let maxOdo = odometers.max(), let minOdo = odometers.min(),
              maxOdo > minOdo else { return nil }
        let km = Double(maxOdo - minOdo)
        return CostPerKmFigure(amount: known.amount, currency: known.currency, km: km)
    }

    // MARK: EV

    /// EV equivalent of the segment engine (docs/SCHEMA.md, Derived: consumption
    /// -> EV): simple kWh/100km over charge sessions where odometer deltas exist.
    /// `litres` carries kWh; per100 is kWh/100km. Sessions with an unresolved
    /// conflict are excluded.
    public static func evSegments(for charges: [ChargeSession]) -> [Segment] {
        let sorted = charges.sorted(by: chargeOrder)
        var result: [Segment] = []
        var open: ChargeSession?
        var pendingKWh = 0.0
        for charge in sorted {
            guard let opening = open else {
                open = charge
                pendingKWh = 0
                continue
            }
            pendingKWh += charge.energyKWh
            defer {
                open = charge
                pendingKWh = 0
            }
            guard opening.conflict == .none, charge.conflict == .none,
                  let openOdo = opening.odometer, let closeOdo = charge.odometer,
                  closeOdo > openOdo else { continue }
            let km = Double(closeOdo - openOdo)
            result.append(Segment(closes: charge.date, km: km, litres: pendingKWh,
                                  openingFillID: opening.id, closingFillID: charge.id))
        }
        return result
    }

    // MARK: Private

    private static func segments(in familyFills: [FillUp], tankCapacityL: Double?) -> [Segment] {
        let tankLevelEnabled = tankCapacityL != nil
        var result: [Segment] = []
        var open: FillUp?
        var openLevelPct: Double?
        var pendingLitres = 0.0
        var touchedConflict = false

        for fill in familyFills {
            // A boundary closes a segment: a full fill always, plus any fill with
            // a known tank level when capacity is set (TANK-LEVEL refinement).
            let isBoundary = fill.isFull || (tankLevelEnabled && fill.tankLevelAfterPct != nil)
            guard let opening = open else {
                guard isBoundary else { continue }
                open = fill
                openLevelPct = fill.tankLevelAfterPct
                pendingLitres = 0
                touchedConflict = false
                continue
            }

            pendingLitres += fill.volumeL
            touchedConflict = touchedConflict || fill.conflict != .none
            guard isBoundary else { continue }
            defer {
                open = fill
                openLevelPct = fill.tankLevelAfterPct
                pendingLitres = 0
                touchedConflict = false
            }
            guard opening.conflict == .none, !touchedConflict,
                  let openOdo = opening.odometer, let closeOdo = fill.odometer,
                  closeOdo > openOdo else { continue }

            let km = Double(closeOdo - openOdo)
            var litres = pendingLitres
            if tankLevelEnabled, let capacity = tankCapacityL,
               let levelOpen = openLevelPct, let levelClose = fill.tankLevelAfterPct {
                litres = pendingLitres + (levelOpen - levelClose) / 100 * capacity
            }
            guard litres >= 0 else { continue }
            result.append(Segment(closes: fill.date, km: km, litres: litres,
                                  openingFillID: opening.id, closingFillID: fill.id))
        }
        return result
    }

    /// The one chronological order both the fill and charge engines read
    /// (`EntryOrder`), so a recompute, the log list and the timeline validator
    /// can never disagree about which same-day fill came first
    /// (docs/SCHEMA.md, Entry -> ordering rule). Odometer ties (a splash fill -
    /// two fills, one date, one reading) fall to creation order, which is
    /// deterministic and never reorders history.
    private static func fillOrder(_ a: FillUp, _ b: FillUp) -> Bool {
        EntryOrder.ascending(a, b)
    }

    private static func chargeOrder(_ a: ChargeSession, _ b: ChargeSession) -> Bool {
        EntryOrder.ascending(a, b)
    }
}
