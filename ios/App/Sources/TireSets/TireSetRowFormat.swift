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

/// The display lines of the set's history (docs/JOURNEYS.md J7b, "The tire
/// set's life"). Each is a full localised phrase, never a concatenation, so
/// word order is the language's own.
enum TireStintFormat {
    /// "12 Mar 2026 – 3 Oct 2026", or "Since 12 Mar 2026" while on the car.
    static func period(_ stint: TireMileage.Stint) -> String {
        let start = ReminderRowFormat.dateString(stint.mountDate)
        guard let end = stint.endDate else {
            return String(format: L10n.localize("Since %@"), start)
        }
        return String(format: L10n.localize("%1$@ – %2$@"), start, ReminderRowFormat.dateString(end))
    }

    /// "Total 18 400 km"; nil while no stint so far has a known distance.
    static func total(_ stint: TireMileage.Stint, distanceUnit: DistanceUnit) -> String? {
        guard let total = stint.totalKm else { return nil }
        return String(format: L10n.localize("Total %@"),
                      TireSetRowFormat.mileageText(km: total, distanceUnit: distanceUnit))
    }

    /// "6.5 mm · even wear", "6.5 mm", "even wear", or nil with no reading.
    static func reading(_ reading: TireReading?) -> String? {
        guard let reading, !reading.isEmpty else { return nil }
        let depth = reading.treadDepthMm.map {
            String(format: L10n.localize("%@ mm"), TireMeasure.depthText($0))
        }
        switch (depth, reading.note) {
        case let (depth?, note?): return String(format: L10n.localize("%@ · %@"), depth, note)
        case let (depth?, nil): return depth
        case let (nil, note?): return note
        case (nil, nil): return nil
        }
    }
}
