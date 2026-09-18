import Foundation

// MARK: - What the headline is made of (RV.118, docs/JOURNEYS.md J8)

/// The one line that turns the headline number into a claim the user can
/// judge: the span it covers, how many of their fills fed it, and how many of
/// those were full tanks. Read straight off the engine's own headline (the
/// span is `Headline.spanDays`, never a second window) and counted over the
/// same counting fills the segments were built from - a coverage computed
/// beside the consumption, not instead of it (hard rule 2, RV.117's defect).
public struct HeadlineProvenance: Equatable, Sendable {
    /// The fills inside the headline's span (or, under the floor, every
    /// counting fill the car has).
    public let fillCount: Int
    /// How many of `fillCount` were full tanks - the fills a segment can
    /// close on.
    public let fullTankCount: Int
    /// The span in days the headline claims; nil under the floor, where there
    /// is no headline and no window to name.
    public let spanDays: Int?
    /// True when no segment has closed: the car has fills but no average, and
    /// the line says "not enough data yet" with the count it does have -
    /// never a computed number.
    public let underFloor: Bool

    public init(fillCount: Int, fullTankCount: Int, spanDays: Int?, underFloor: Bool) {
        self.fillCount = fillCount
        self.fullTankCount = fullTankCount
        self.spanDays = spanDays
        self.underFloor = underFloor
    }

    /// Derives the line for a headline over `countingFills` (the S2-counted
    /// fills the engine saw). `nil` when the car has no fills at all - a
    /// provenance for nothing is noise.
    public static func derive(headline: Headline?, countingFills: [FillUp], asOf: Date) -> HeadlineProvenance? {
        guard !countingFills.isEmpty else { return nil }
        guard let headline else {
            return HeadlineProvenance(fillCount: countingFills.count,
                                      fullTankCount: countingFills.filter(\.isFull).count,
                                      spanDays: nil, underFloor: true)
        }
        let start = asOf.addingTimeInterval(-Double(headline.spanDays) * 86_400)
        let inSpan = countingFills.filter { $0.date >= start && $0.date <= asOf }
        return HeadlineProvenance(fillCount: inSpan.count,
                                  fullTankCount: inSpan.filter(\.isFull).count,
                                  spanDays: headline.spanDays, underFloor: false)
    }
}
