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
}
