import Foundation

/// The plausible tank-average consumption band per powertrain - the F2
/// residue's "consumption outlier check on save" (docs/JOURNEYS.md F2, "The
/// residue"; docs/SCHEMA.md, Validation -> CHECK 5).
///
/// The band is a HINT threshold, never a gate: a value outside it raises the
/// same non-blocking `warn` a timeline flag does, and the entry still saves
/// (docs/SCHEMA.md, "Bands are wide and soft on purpose"; hard rule 13).
///
/// **Placement (docs/PRACTICES.md section 6).** This is *meaning*, not tuning -
/// like the consumption model's window and floor - so it is a tier-C compiled
/// constant, one definition, changed only with a doc change. It is deliberately
/// NOT remote config (`CONFIG.md` forbids consumption math there) and NOT a
/// per-user setting: a user cannot be asked to know their car's plausible
/// L/100km band, and a wrong band would silently redefine when the hint fires.
///
/// **Why per powertrain, and why this wide.** `Vehicle.powertrain` is the one
/// fact the schema carries that separates a car which can plausibly run at
/// under 2 L/100km (a plug-in hybrid on a mostly-electric tank) from one that
/// cannot (a combustion-only car). The ranges are deliberately generous at the
/// edges: this check exists to catch a misread DIGIT (the F2 case - a litre or
/// an odometer off by a factor), not to rank ordinary variation, and a false
/// hint erodes trust faster than a missed one. A price outlier can never trip
/// it: consumption is litres over distance, and the money is never read.
public enum ConsumptionOutlier {

    /// The plausible L/100km range for a powertrain (kWh/100km for an EV, whose
    /// `Segment.litres` carries kWh - docs/SCHEMA.md, SEGMENT).
    public static func plausibleRange(for powertrain: Powertrain) -> ClosedRange<Double> {
        switch powertrain {
        case .ice:
            // A combustion-only tank below 2.5 L/100km is a factor out of range
            // (the record-holding production cars sit at ~3, and the F2 misread
            // 42.3 -> 12.3 lands below this on a normal tank); above 40 is a
            // race car or a misread volume.
            return 2.5...40
        case .hybrid:
            return 1.0...40
        case .phev:
            // A plug-in can cover a tank almost entirely on electricity.
            return 0.3...40
        case .ev:
            // A FillUp on an EV carries electricity, so the figure is
            // kWh/100km: an order of magnitude larger than litres.
            return 5.0...60
        }
    }

    /// Clears only a `.consumption` conflict, leaving order/pace in place.
    ///
    /// The outlier check reads the segment the fill closes. A `.consumption`
    /// conflict excludes that segment from `ConsumptionEngine` - the engine
    /// drops any segment touching a flag - so without this the hint would
    /// suppress its own evidence and clear on the next `revalidateTimeline`.
    /// An order/pace conflict is deliberately NOT cleared: a segment built on
    /// an untrustworthy odometer or date is a timeline question, not a
    /// consumption one.
    static func clearingSoftConflict(_ fill: FillUp) -> FillUp {
        guard case .flagged(.consumption, _) = fill.conflict else { return fill }
        var cleared = fill
        cleared.conflict = .none
        return cleared
    }
}
