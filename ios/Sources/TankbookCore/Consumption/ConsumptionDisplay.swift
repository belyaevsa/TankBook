import Foundation

// MARK: - The one per100 -> display-unit conversion (RV.296, docs/SCHEMA.md)

/// The engine computes `per100` (L/100km, kWh/100km) and nothing else. A car
/// set to MPG or km/L reads its figures through THIS conversion and nowhere
/// else - RV.134's rule one seam over: a figure printed beside a unit label
/// must be in that unit. MPG and km/L are the inverse of per100, so "lower is
/// better" becomes "higher is better" for them: `isInverted` is what a trend
/// arrow and a delta must consult before drawing a direction.
public enum ConsumptionDisplay {
    /// Litres per 100 km -> miles per US gallon: 235.215 / per100.
    public static let mpgUSNumerator = 235.215
    /// Litres per 100 km -> miles per imperial gallon: 282.481 / per100.
    public static let mpgUKNumerator = 282.481

    /// The displayed figure for a per100 in the car's headline unit. A zero
    /// per100 in an inverted unit has no finite value; the engine never
    /// produces one (a segment needs km > 0), so it maps to 0 rather than
    /// infinity to keep a renderer honest about "nothing".
    public static func value(per100: Double, unit: HeadlineUnit) -> Double {
        switch unit {
        case .energyPer100, .consumption(.lPer100):
            return per100
        case .consumption(.mpgUS):
            return per100 > 0 ? mpgUSNumerator / per100 : 0
        case .consumption(.mpgUK):
            return per100 > 0 ? mpgUKNumerator / per100 : 0
        case .consumption(.kmPerL):
            return per100 > 0 ? 100 / per100 : 0
        }
    }

    /// True for the units where a HIGHER figure is the better one (MPG, km/L).
    public static func isInverted(_ unit: HeadlineUnit) -> Bool {
        switch unit {
        case .energyPer100, .consumption(.lPer100): return false
        case .consumption(.mpgUS), .consumption(.mpgUK), .consumption(.kmPerL): return true
        }
    }

    /// The displayed figure rounded to the tile's precision (one decimal).
    public static func rounded(per100: Double, unit: HeadlineUnit) -> Double {
        (value(per100: per100, unit: unit) * 10).rounded() / 10
    }

    /// The unsigned percent by which the DISPLAYED figure moved between two
    /// per100 values - what a "▼20%" beside an MPG figure must mean. For
    /// L/100 it is the per100 percent; for an inverted unit it is the percent
    /// of the inverse, which differs (a 20% drop in L/100 is a 25% rise in MPG).
    public static func displayedPercentChange(fromPer100 previous: Double, toPer100 current: Double,
                                              unit: HeadlineUnit) -> Double? {
        let before = value(per100: previous, unit: unit)
        let after = value(per100: current, unit: unit)
        guard before > 0 else { return nil }
        return abs(after - before) / before * 100
    }
}
