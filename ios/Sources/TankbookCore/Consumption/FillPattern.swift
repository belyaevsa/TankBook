import Foundation

// MARK: - The fill pattern (RV.120, docs/JOURNEYS.md J8)

/// How far between fills, how often, how far the tank goes, what the month
/// will cost - each derived locally over the same window the headline claims
/// and each ABSENT, never zeroed, when the data cannot yield it honestly
/// (docs/SCHEMA.md -> FILL PATTERN). Nothing is offered for a car under the
/// consumption floor: that is precisely the car whose numbers are noise.
public struct FillPattern: Equatable, Sendable {
    /// Mean odometer distance between consecutive fills in the window, km.
    /// Absent below two fills with odometers.
    public let kmBetweenFills: Int?
    /// Mean days between consecutive fills in the window. Absent below two.
    public let daysBetweenFills: Double?
    /// The estimated distance left on the last full tank: the tank's capacity
    /// at the headline's consumption, less the distance driven since. Absent
    /// unless the capacity is CORROBORATED by the user's own fills
    /// (`capacityIsCorroborated`), there is a full fill to count from, an
    /// odometer since it, and the estimate is positive.
    public let rangeLeftKm: Int?
    /// The month's spend on this month's pace - a PREDICTION, labelled as one
    /// by the caller: the complete spend so far scaled to the whole month.
    /// Absent before day 7, below two money-bearing entries this month, or
    /// when the month's total is not exact.
    public let monthForecast: MonthForecast?

    public struct MonthForecast: Equatable, Sendable {
        public let amount: Decimal
        public let currency: CurrencyCode
        /// The days the pace was measured over.
        public let daysElapsed: Int

        public init(amount: Decimal, currency: CurrencyCode, daysElapsed: Int) {
            self.amount = amount
            self.currency = currency
            self.daysElapsed = daysElapsed
        }
    }

    public init(kmBetweenFills: Int?, daysBetweenFills: Double?, rangeLeftKm: Int?, monthForecast: MonthForecast?) {
        self.kmBetweenFills = kmBetweenFills
        self.daysBetweenFills = daysBetweenFills
        self.rangeLeftKm = rangeLeftKm
        self.monthForecast = monthForecast
    }

    public var isEmpty: Bool {
        kmBetweenFills == nil && daysBetweenFills == nil && rangeLeftKm == nil && monthForecast == nil
    }

    /// The forecast needs this many days of the month before a pace exists.
    public static let forecastMinimumDays = 7
    /// A logged full fill this close to the stated capacity corroborates it.
    public static let corroborationRatio = 0.8
    /// A fill this far above the stated capacity refutes it.
    public static let refutationRatio = 1.05

    // MARK: Derivation

    /// What the derivation reads: the engine's headline, the S2-counted fills
    /// it saw, the car's odometer and stated tank, and the same typed month
    /// total Home shows.
    public struct Inputs {
        public var headline: Headline?
        public var countingFills: [FillUp]
        public var currentOdometer: Int?
        public var tankCapacityL: Double?
        public var monthSpend: LogStream.MonthTotal?

        public init(headline: Headline?, countingFills: [FillUp], currentOdometer: Int?,
                    tankCapacityL: Double?, monthSpend: LogStream.MonthTotal?) {
            self.headline = headline
            self.countingFills = countingFills
            self.currentOdometer = currentOdometer
            self.tankCapacityL = tankCapacityL
            self.monthSpend = monthSpend
        }
    }

    /// `nil` under the floor (no headline).
    public static func derive(_ inputs: Inputs, asOf: Date, calendar: Calendar) -> FillPattern? {
        guard let headline = inputs.headline else { return nil }
        let countingFills = inputs.countingFills
        let start = asOf.addingTimeInterval(-Double(headline.spanDays) * 86_400)
        let sorted = countingFills.filter { $0.date <= asOf }.sorted(by: EntryOrder.ascending)
        // The window's fills plus the one that opened it: the headline's span
        // runs from its earliest CLOSING fill, and the gap before that fill is
        // part of the pattern too.
        let opener = sorted.last { $0.date < start }.map { [$0] } ?? []
        let inWindow = opener + sorted.filter { $0.date >= start }
        return FillPattern(
            kmBetweenFills: meanKmBetween(inWindow),
            daysBetweenFills: meanDaysBetween(inWindow),
            rangeLeftKm: rangeLeft(fills: countingFills, per100: headline.value,
                                   currentOdometer: inputs.currentOdometer, tankCapacityL: inputs.tankCapacityL),
            monthForecast: forecast(monthSpend: inputs.monthSpend, asOf: asOf, calendar: calendar,
                                    countingFills: countingFills))
    }

    static func meanKmBetween(_ fills: [FillUp]) -> Int? {
        let odometers = fills.compactMap(\.odometer)
        guard odometers.count >= 2 else { return nil }
        let deltas = zip(odometers.dropFirst(), odometers).map { $0 - $1 }.filter { $0 > 0 }
        guard !deltas.isEmpty else { return nil }
        return Int((Double(deltas.reduce(0, +)) / Double(deltas.count)).rounded())
    }

    static func meanDaysBetween(_ fills: [FillUp]) -> Double? {
        guard fills.count >= 2, let first = fills.first, let last = fills.last,
              last.date > first.date else { return nil }
        return last.date.timeIntervalSince(first.date) / 86_400 / Double(fills.count - 1)
    }

    /// The stated capacity counts only when the user's own fills corroborate
    /// it: some full fill reached `corroborationRatio` of it, and none exceeded
    /// `refutationRatio` of it. A catalog figure nobody ever filled that far
    /// is a guess, and a range built on a guess is confidently wrong (hard
    /// rule 13) - so it is absent instead.
    public static func capacityIsCorroborated(_ capacity: Double?, fills: [FillUp]) -> Bool {
        guard let capacity, capacity > 0 else { return false }
        let volumes = fills.map(\.volumeL)
        guard let largest = volumes.max(), largest >= capacity * corroborationRatio else { return false }
        return !volumes.contains { $0 > capacity * refutationRatio }
    }

    static func rangeLeft(fills: [FillUp], per100: Double, currentOdometer: Int?,
                          tankCapacityL: Double?) -> Int? {
        guard per100 > 0, capacityIsCorroborated(tankCapacityL, fills: fills), let capacity = tankCapacityL,
              let lastFull = fills.filter(\.isFull).max(by: EntryOrder.ascending),
              let fullOdometer = lastFull.odometer, let currentOdometer, currentOdometer >= fullOdometer
        else { return nil }
        let tankRange = capacity / per100 * 100
        let left = tankRange - Double(currentOdometer - fullOdometer)
        guard left > 0 else { return nil }
        return Int(left.rounded())
    }

    static func forecast(monthSpend: LogStream.MonthTotal?, asOf: Date, calendar: Calendar,
                         countingFills: [FillUp]) -> MonthForecast? {
        guard case .complete(let amount, let currency)? = monthSpend, amount > 0,
              let month = calendar.dateInterval(of: .month, for: asOf),
              let dayOfMonth = calendar.dateComponents([.day], from: asOf).day,
              dayOfMonth >= forecastMinimumDays,
              let daysInMonth = calendar.range(of: .day, in: .month, for: asOf)?.count else { return nil }
        let moneyBearing = countingFills.filter { month.contains($0.date) && $0.money != nil }.count
        guard moneyBearing >= 2 else { return nil }
        let scaled = amount / Decimal(dayOfMonth) * Decimal(daysInMonth)
        var rounded = Decimal()
        var source = scaled
        NSDecimalRound(&rounded, &source, 0, .plain)
        return MonthForecast(amount: rounded, currency: currency, daysElapsed: dayOfMonth)
    }
}
