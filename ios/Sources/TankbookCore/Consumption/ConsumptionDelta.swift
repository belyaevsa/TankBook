import Foundation

/// Display-level comparison of two recompute results (docs/SCHEMA.md,
/// Recalculation on edit: "the edit screen confirms with the delta"). A figure
/// "actually changed" only when the DISPLAYED values differ - the same
/// precision the tile shows - because an edit that moves nothing must not claim
/// an update (docs/ERRORS.md -> Edit entry, row 4). Old and new both come from
/// the engine; this type only rounds and compares, it adds no arithmetic.
public enum ConsumptionDelta {
    /// The headline value rounded to the displayed 1-decimal precision,
    /// or `nil` when no headline exists (below the data floor).
    public static func displayedValue(_ headline: Headline?) -> Double? {
        guard let value = headline?.value else { return nil }
        return (value * 10).rounded() / 10
    }

    /// True when the two recompute results differ at display precision - the
    /// toast-suppression case. A missing headline on either side is no delta:
    /// going from "no number" to "a first estimate" is a real event, but the
    /// documented toast is about a shifted figure, not an appearing one.
    public static func hasChanged(before: Headline?, after: Headline?) -> Bool {
        guard let beforeValue = displayedValue(before),
              let afterValue = displayedValue(after) else {
            return false
        }
        return beforeValue != afterValue
    }
}
