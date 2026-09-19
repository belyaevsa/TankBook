import Foundation

// MARK: - The month divider's glance (RV.119, docs/JOURNEYS.md J8)

/// What a month's divider may say beyond its spend: the distance its rows
/// span, the consumption of the segments that closed in it, its cost per
/// kilometre, and how its spend compares with the month before. Every figure
/// is derived from the rows the section already holds (hard rule 2) and every
/// figure is ABSENT, never zero or a dash, when the month cannot yield it
/// honestly - the comparison most of all, because a partial month, a
/// rate-pending month or a month with one fill compared as if complete is
/// the number that lies.
public struct MonthGlance: Equatable, Sendable {
    /// Distance between the month's first and last logged odometers, km.
    /// Absent below two odometer readings.
    public let distanceKm: Int?
    /// Distance-weighted consumption of the segments that CLOSED in the
    /// month (Σ litres / Σ km x 100 - the engine's own segments, so a row's
    /// per-fill figure and its divider agree). Absent when none closed.
    public let per100: Double?
    /// Spend per kilometre: the month's `.complete` total over `distanceKm`.
    /// Absent unless the total is exact and the distance is known and positive.
    public let costPerKm: CostPerKmFigure?
    /// The spend against the previous calendar month, as a rounded percent
    /// (negative = lower). Absent unless BOTH months are `.complete` in the
    /// same currency, both hold at least two counting fills, the previous
    /// spend is positive, and this month is over (the month in progress is
    /// never compared - its total is not final).
    public let spendDelta: SpendDelta?

    public struct SpendDelta: Equatable, Sendable {
        public let percent: Int
        public let previousMonthStart: Date

        public init(percent: Int, previousMonthStart: Date) {
            self.percent = percent
            self.previousMonthStart = previousMonthStart
        }
    }

    public init(distanceKm: Int?, per100: Double?, costPerKm: CostPerKmFigure?, spendDelta: SpendDelta?) {
        self.distanceKm = distanceKm
        self.per100 = per100
        self.costPerKm = costPerKm
        self.spendDelta = spendDelta
    }

    /// True when the glance has nothing to say - the divider then prints its
    /// spend alone, exactly as before.
    public var isEmpty: Bool {
        distanceKm == nil && per100 == nil && costPerKm == nil && spendDelta == nil
    }

    // MARK: Derivation

    /// The glances for every month with rows, keyed by month start. `totals`
    /// are the sections' own typed spend figures, `entries` the counting
    /// entries (S2-excluded members never count), `segments` the engine's.
    static func derive(totals: [Date: LogStream.MonthTotal], entries: [any Entry], segments: [Segment],
                       asOf: Date, calendar: Calendar) -> [Date: MonthGlance] {
        func monthStart(_ date: Date) -> Date {
            calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
        let context = Context(totals: totals,
                              entriesByMonth: Dictionary(grouping: entries, by: { monthStart($0.date) }),
                              currentMonth: monthStart(asOf), calendar: calendar)
        let segmentsByMonth = Dictionary(grouping: segments, by: { monthStart($0.closes) })

        var out: [Date: MonthGlance] = [:]
        for (month, total) in totals {
            let inMonth = context.entriesByMonth[month] ?? []
            let odometers = inMonth.compactMap(\.odometer)
            var distance: Int?
            if odometers.count >= 2, let high = odometers.max(), let low = odometers.min(), high > low {
                distance = high - low
            }
            var per100: Double?
            if let closed = segmentsByMonth[month], !closed.isEmpty {
                let km = closed.reduce(0) { $0 + $1.km }
                let litres = closed.reduce(0) { $0 + $1.litres }
                if km > 0 { per100 = litres / km * 100 }
            }
            var costPerKm: CostPerKmFigure?
            if case .complete(let amount, let currency) = total, let distance, amount > 0 {
                costPerKm = CostPerKmFigure(amount: amount, currency: currency, km: Double(distance))
            }
            let delta = spendDelta(month: month, total: total, context: context)
            out[month] = MonthGlance(distanceKm: distance, per100: per100, costPerKm: costPerKm, spendDelta: delta)
        }
        return out
    }

    private struct Context {
        let totals: [Date: LogStream.MonthTotal]
        let entriesByMonth: [Date: [any Entry]]
        let currentMonth: Date
        let calendar: Calendar
    }

    private static func spendDelta(month: Date, total: LogStream.MonthTotal, context: Context) -> SpendDelta? {
        guard month < context.currentMonth,
              case .complete(let amount, let currency) = total,
              let previousMonth = context.calendar.date(byAdding: .month, value: -1, to: month),
              case .complete(let previousAmount, let previousCurrency)? = context.totals[previousMonth],
              previousCurrency == currency, previousAmount > 0 else { return nil }
        func fillCount(_ month: Date) -> Int {
            (context.entriesByMonth[month] ?? []).filter { $0 is FillUp }.count
        }
        guard fillCount(month) >= 2, fillCount(previousMonth) >= 2 else { return nil }
        let ratio = (amount - previousAmount) / previousAmount * 100
        let percent = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
        return SpendDelta(percent: percent, previousMonthStart: previousMonth)
    }
}

extension LogStream {
    /// RV.119: the glance per whole month, derived once and attached to each
    /// full section. In the glance's file so the stream's own body stays
    /// within the linter's ceiling.
    static func attachingGlances(to sections: [Section], entries: [any Entry], segments: [Segment],
                                 asOf: Date, calendar: Calendar) -> [Section] {
        let totals = Dictionary(uniqueKeysWithValues: sections.map { ($0.monthStart, $0.total) })
        let glances = MonthGlance.derive(totals: totals, entries: entries, segments: segments,
                                         asOf: asOf, calendar: calendar)
        return sections.map {
            Section(monthStart: $0.monthStart, total: $0.total, rows: $0.rows, glance: glances[$0.monthStart])
        }
    }
}
