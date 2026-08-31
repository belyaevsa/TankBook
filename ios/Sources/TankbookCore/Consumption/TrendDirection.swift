import Foundation

/// The direction a trend series is moving, as announced to VoiceOver
/// (docs/DESIGN.md -> Accessibility floor: "consumption 6.8 liters per 100
/// kilometers, improving"). A bare number read aloud is useless; the direction
/// is the half that makes the figure mean something.
///
/// "Improving" only exists for a metric where lower is better - consumption,
/// cost per km, unit price. It is derived from the same series the figure is
/// drawn from, never stored (hard rule 2), and it abstains rather than invent:
/// fewer than two points, a flat series, or a change under 1% report `nil`, so
/// VoiceOver never announces a "trend" the data does not support. A nil trend
/// is silently omitted from the label, never read as "steady".
public enum TrendDirection: Equatable, Sendable {
    case improving
    case worsening

    /// The trend of a lower-is-better series from its last two points.
    /// `nil` with fewer than two points, a flat series, or a negligible
    /// (under 1%) change - a difference that small is rounding noise, not a
    /// direction.
    public static func lowerIsBetter(_ series: [Double]) -> TrendDirection? {
        guard series.count >= 2 else { return nil }
        let last = series[series.count - 1]
        let previous = series[series.count - 2]
        let delta = last - previous
        let scale = max(abs(previous), abs(last))
        guard scale > 0, abs(delta) / scale >= 0.01 else { return nil }
        return delta < 0 ? .improving : .worsening
    }
}
