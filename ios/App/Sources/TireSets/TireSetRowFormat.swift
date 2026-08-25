import Foundation
import TankbookCore

/// The display line of a tire-set row: its derived mileage (P3.3). The set's
/// name is runtime data the row renders itself; the mileage is the number plus
/// its unit when known, and "–" when the set has never been mounted or has no
/// usable span (zero is a claim, and it is false - docs/SCHEMA.md, docs/
/// JOURNEYS.md J7b: "Tire mileage without logged swaps -> unavailable, shown as
/// '–', never estimated").
///
/// The number is grouped with the shared `OdometerFormat` (U+00A0 separator);
/// the unit resolves through the catalogue so "km" renders "км" in Russian. The
/// returned value is already localised, so the row renders it through
/// `Text(_: String)` - there is no English key hiding here (the trap at the top
/// of `L10n.swift`).
enum TireSetRowFormat {
    /// "18 400 km" when known, "–" when unknowable.
    static func mileageText(km: Int?, distanceUnit: DistanceUnit) -> String {
        guard let km else { return L10n.localize("–") }
        return "\(OdometerFormat.grouped(km)) \(L10n.distanceUnit(distanceUnit))"
    }
}
