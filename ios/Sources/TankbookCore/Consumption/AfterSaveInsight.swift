import Foundation

/// The one-liner a fill-up save earns (docs/JOURNEYS.md J3 → Done: "the
/// insight one-liner is the habit hook, not the stored row"). Every case is
/// read off the engine's own figures for the saved fill; when the data says
/// nothing yet the answer is `nil` and the save shows no toast - a number is
/// never fabricated to have something to say.
public enum AfterSaveInsight: Equatable, Sendable {
    /// The saved fill closed a segment: its consumption, and whether that
    /// figure is the best (lowest) of the calendar year at display precision.
    case segmentClosed(per100: Double, isBestThisYear: Bool)
    /// The saved fill is a full tank and no segment has closed yet - the D4
    /// state Home also names ("One more full tank and your consumption
    /// appears").
    case needsAnotherFullTank

    /// `stats` is the derivation over the entries AFTER the save, so the saved
    /// fill is among them; `saved` is the fill the save wrote.
    public static func derive(saved: FillUp, stats: HomeStats) -> AfterSaveInsight? {
        if let segment = stats.segments.first(where: { $0.closingFillID == saved.id }) {
            let displayed = displayedPer100(segment.per100)
            let best = stats.bestThisYear.map(displayedPer100)
            return .segmentClosed(per100: segment.per100,
                                  isBestThisYear: best.map { displayed <= $0 } ?? false)
        }
        if saved.isFull && stats.needsAnotherFullTank {
            return .needsAnotherFullTank
        }
        return nil
    }

    /// The precision the tile prints (one decimal): "best" is judged at the
    /// precision the user can see, so a tie at 6.8 reads as best, not as a
    /// miss by 0.03.
    static func displayedPer100(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
