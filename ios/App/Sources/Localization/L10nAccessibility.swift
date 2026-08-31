import Foundation
import TankbookCore

// MARK: - VoiceOver units and trend (P6.5)

extension L10n {
    /// The SPOKEN form of a headline unit, for VoiceOver labels only. The
    /// visible form is the compact "L/100km"; read aloud that is "L one hundred
    /// k m", which is noise. The floor (docs/DESIGN.md -> Accessibility floor)
    /// names the shape: "consumption 6.8 liters per 100 kilometers, improving".
    /// These strings never render on screen - they exist so the accessibility
    /// label reads the unit as a human would say it.
    static func spokenHeadlineUnit(_ unit: HeadlineUnit) -> String {
        switch unit {
        case .energyPer100: localize("kilowatt-hours per 100 kilometers")
        case .consumption(.lPer100): localize("liters per 100 kilometers")
        case .consumption(.mpgUS): localize("miles per gallon (US)")
        case .consumption(.mpgUK): localize("miles per gallon (UK)")
        case .consumption(.kmPerL): localize("kilometers per liter")
        }
    }

    /// The VoiceOver word for a trend direction, appended to a metric's label
    /// ("…, improving" / "…, worsening"). Lower-is-better metrics only; a nil
    /// direction is omitted entirely, never read as "steady" (a word the data
    /// did not earn).
    static func trend(_ direction: TrendDirection) -> String {
        switch direction {
        case .improving: localize("improving")
        case .worsening: localize("worsening")
        }
    }
}
