import TankbookCore

/// RV.134: the Confirm sheet's unit-aware copy. Each sentence exists once per
/// unit, never as a unit token spliced into a shared stem (hard rule 10): RU
/// declines the units differently ("км" is indeclinable, "миль" a genitive
/// plural, "л"/"гал" abbreviations), so the sentence - not the unit label - is
/// the translation unit. Each function returns the already-localised phrase, so
/// the view renders it verbatim and the L1 tests pin the unit -> phrase mapping.
enum ManualFillUpUnitCopy {
    /// The price row's label, per volume unit.
    static func priceLabel(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Price / L")
        case .galUS, .galUK: L10n.localize("Price / gal")
        }
    }

    /// The "fills in from total ÷ …" caption under an empty price row.
    static func fillsFromTotal(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("fills in from total ÷ liters")
        case .galUS, .galUK: L10n.localize("fills in from total ÷ gallons")
        }
    }

    /// The rendered "+N <unit> since last" caption. One full localised sentence
    /// per unit - the count governs the unit's declension in RU, so the phrase
    /// cannot share a stem with an interpolated unit token.
    static func deltaSinceLast(_ unit: DistanceUnit, km: Int) -> String {
        switch unit {
        case .km: String(localized: "+\(km) km since last")
        case .mi: String(localized: "+\(km) mi since last")
        }
    }
}
