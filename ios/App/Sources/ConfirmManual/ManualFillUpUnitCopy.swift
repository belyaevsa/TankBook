import SwiftUI
import TankbookCore

/// RV.134/RV.234: unit-aware copy. Each sentence exists once per unit, never as
/// a unit token spliced into a shared stem (hard rule 10): RU declines the units
/// differently ("км" is indeclinable, "миль" a genitive plural, "л"/"гал"
/// abbreviations), so the sentence - not the unit label - is the translation
/// unit. Each function returns the already-localised phrase, so the view renders
/// it verbatim and the L1 tests pin the unit -> phrase mapping.
enum ManualFillUpUnitCopy {
    // MARK: Volume labels and hints

    /// The volume row's label on the Confirm numbers card.
    static func volumeLabel(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Liters")
        case .galUS, .galUK: L10n.localize("Gallons")
        }
    }

    /// The disabled-save hint, per volume unit.
    static func enterTotalAndVolume(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Enter total and liters to save")
        case .galUS, .galUK: L10n.localize("Enter total and gallons to save")
        }
    }

    /// The VoiceOver label on the volume field's tap-to-verify button.
    static func checkVolumeOnReceipt(for unit: VolumeUnit) -> LocalizedStringKey {
        switch unit {
        case .l: "Check the liters on the receipt"
        case .galUS, .galUK: "Check the gallons on the receipt"
        }
    }

    /// The CHECK 5 ranked fix ("Check litres" / "Check gallons").
    static func checkVolumeChip(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Check litres")
        case .galUS, .galUK: L10n.localize("Check gallons")
        }
    }

    // MARK: Price and cost labels

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

    /// Home's last-price vital label.
    static func lastPriceLabel(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Last price/L")
        case .galUS, .galUK: L10n.localize("Last price/gal")
        }
    }

    /// The all-in cost label, per distance unit.
    static func costPerDistanceLabel(for unit: DistanceUnit) -> String {
        switch unit {
        case .km: L10n.localize("Cost / km")
        case .mi: L10n.localize("Cost / mi")
        }
    }

    /// Home guest's per-distance vital label.
    static func perDistanceLabel(for unit: DistanceUnit) -> String {
        switch unit {
        case .km: L10n.localize("per km")
        case .mi: L10n.localize("per mi")
        }
    }

    // MARK: Tank level

    /// "≈ 53 of 71 L" / "≈ 14 of 19 gal" - the tank-level equivalence.
    static func tankEquivalence(volume: Int, capacity: Int, unit: VolumeUnit) -> String {
        switch unit {
        case .l:
            String(format: L10n.localize("≈ %d of %d L"), volume, capacity)
        case .galUS, .galUK:
            String(format: L10n.localize("≈ %d of %d gal"), volume, capacity)
        }
    }

    /// The ERRORS.md hint when no tank capacity is set, per volume unit.
    static func setTankSizeHint(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Set tank size in Garage to see liters.")
        case .galUS, .galUK: L10n.localize("Set tank size in Garage to see gallons.")
        }
    }

    // MARK: Consumption outlier (CHECK 5)

    /// The consumption-outlier sentence: the engine's figure and unit, then the
    /// two fields that can be wrong. One full sentence per volume unit, never a
    /// shared stem with the unit word swapped in.
    static func consumptionQuote(per100: String, unit: String, volumeUnit: VolumeUnit) -> String {
        switch volumeUnit {
        case .l:
            String(format: L10n.localize("This fill implies %1$@ %2$@ – check the litres or the odometer."),
                   per100, unit)
        case .galUS, .galUK:
            String(format: L10n.localize("This fill implies %1$@ %2$@ – check the gallons or the odometer."),
                   per100, unit)
        }
    }

    /// The excluded/flagged consumption reason caption.
    static func consumptionReason(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Unusual consumption – check the litres or odometer")
        case .galUS, .galUK: L10n.localize("Unusual consumption – check the gallons or odometer")
        }
    }

    // MARK: Field labels (the recognised page and the import review)

    /// `FieldLabel`'s volume cell.
    static func fieldVolumeLabel(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Litres")
        case .galUS, .galUK: L10n.localize("Gallons")
        }
    }

    /// `FieldLabel`'s unit-price cell.
    static func fieldPriceLabel(for unit: VolumeUnit) -> String {
        switch unit {
        case .l: L10n.localize("Price/L")
        case .galUS, .galUK: L10n.localize("Price/gal")
        }
    }

    // MARK: Distance delta

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
