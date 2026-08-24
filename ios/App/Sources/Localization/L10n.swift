import Foundation
import TankbookCore

/// String Catalog access for composed display strings. Standalone phrases go
/// through `Text(LocalizedStringKey)`; composed rows (units, suggestion subtitles)
/// read the same catalog through the bundle. Every key here has an EN + RU
/// entry in Localizable.xcstrings.
enum L10n {
    static func localize(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func distanceUnit(_ unit: DistanceUnit) -> String {
        switch unit {
        case .km: localize("km")
        case .mi: localize("mi")
        }
    }

    static func volumeUnit(_ unit: VolumeUnit) -> String {
        switch unit {
        case .l: localize("L")
        case .galUS, .galUK: localize("gal")
        }
    }

    static func consumptionUnit(_ unit: ConsumptionUnit) -> String {
        switch unit {
        case .lPer100: localize("L/100km")
        case .mpgUS, .mpgUK: localize("MPG")
        case .kmPerL: localize("km/L")
        }
    }

    static var kWh: String { localize("kWh") }

    /// "1 entry excluded" / "2 entries excluded" - the Home footnote for
    /// entries excluded from a figure. Real plural rules per language
    /// (Russian has three forms) via the String Catalog's "%lld entries
    /// excluded" plural variations - never concatenation (the RU pass on P1.4
    /// proved composed strings need a full localised phrase per language).
    static func entriesExcluded(_ count: Int) -> String {
        String(localized: "\(count) entries excluded")
    }

    /// The honest consumption-span label, localized (docs/SCHEMA.md ->
    /// HEADLINE; docs/ERRORS.md -> Trends). Shared by Home and Trends so they
    /// render the identical wording from one place. `Headline.Label.honestText()`
    /// is the same rule in the default language; this is the catalog-backed
    /// rendering with real plural rules per language ("last 5 months", never
    /// "last 3 months" for an extended window; "first estimate · 1 fill cycle").
    static func honestSpanLabel(_ label: Headline.Label) -> String {
        switch label {
        case .window(let months):
            return String(localized: "last \(months) months")
        case .firstEstimate(let cycles):
            return String(localized: "first estimate · \(cycles) fill cycles")
        }
    }
}
