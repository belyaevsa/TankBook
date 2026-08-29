import Foundation
import SwiftUI
import TankbookCore

/// Which Add car field currently holds focus (drives suggestions + field
/// underlines). Internal so the section subviews can share it.
enum AddVehicleFocus: Hashable {
    case name, makeModel, plate, odometer, capacity
}

// MARK: - Form state

/// Everything the Add car screen collects, plus the warning computations that
/// drive the three ERRORS.md states. Warnings are derived so they cannot drift
/// from the input; nothing here blocks save (docs/ERRORS.md -> Add car).
struct AddVehicleFormState {
    var name = ""
    var makeModel = ""
    var plate = ""
    var make: String?
    var model: String?
    var year: Int?
    var powertrain: Powertrain = .ice
    var selectedFuelKinds: Set<FuelKind>
    var odometer = ""
    var odometerTouched = false
    var odometerConfirmed = false
    var saveAttempted = false
    var homeCurrency: CurrencyCode
    var capacity = ""
    var photo: Data?

    /// The locale-driven defaults (docs/JOURNEYS.md J1): home currency from
    /// the device locale, and the RU locale's two common petrol grades beside
    /// the RUB guess (PJ.3). Both are default inputs the user edits (hard rule
    /// 13) - never facts.
    init(locale: Locale = .current) {
        homeCurrency = LocaleCurrency.defaultCurrency(for: locale)
        selectedFuelKinds = Set(VehicleDefaults.defaultFuelKinds(for: locale))
    }

    // MARK: Error-state 1: name empty on save (warn, never blocks forever)

    /// The warn shows after a failed save attempt and clears the moment a name
    /// is typed ("save re-enables live" - docs/ERRORS.md).
    var showNameWarning: Bool { name.isEmpty && saveAttempted }

    // MARK: Error-state 2: odometer missing/implausible (warn, never blocks)

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        // Format-on-blur puts a thin-space grouped string back into the field
        // (HANDOVER.md open item 0); grouping is DISPLAY only, so the model
        // strips it before parsing.
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    var odometerIsImplausible: Bool {
        guard let odometerValue else { return false }
        return OdometerPlausibility.isImplausible(odometerValue, year: year)
    }

    var odometerNeedsAttention: Bool { odometer.isEmpty || odometerIsImplausible }

    /// Shown once the user has engaged with the field or tried to save; a
    /// "confirm it's right" tap dismisses it for this car. It never blocks save.
    var showOdometerWarning: Bool {
        guard !odometerConfirmed else { return false }
        guard odometerTouched || saveAttempted else { return false }
        return odometerNeedsAttention
    }

    /// The vehicle's units, derived from the device locale (US -> imperial,
    /// everywhere else metric). The Add car artboard shows the result
    /// ("km · L · L/100km"); per-car editing arrives with Vehicle detail.
    static func units(for locale: Locale = .current) -> Vehicle.Units {
        if locale.region?.identifier.uppercased() == "US" {
            return Vehicle.Units(distance: .mi, volume: .galUS, consumption: .mpgUS, energy: .miPerKWh)
        }
        return Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100)
    }
}

// MARK: - Error-state 2 support

/// Soft plausibility bound for the "Current odometer" field
/// (docs/ERRORS.md -> Add car: "12 km on a 2015 car"). A deliberately low bar -
/// 100 km per year of age - so it only fires on clearly impossible readings and
/// never on a genuinely new car ("confirm it's right (one tap - new cars exist)").
enum OdometerPlausibility {
    static func isImplausible(_ odometer: Int, year: Int?,
                              currentYear: Int = Calendar.current.component(.year, from: Date())) -> Bool {
        guard let year, year <= currentYear else { return false }
        return odometer < (currentYear - year) * 100
    }
}

// MARK: - Make · model · year parsing

/// Structured result of parsing the free-text "Make · model · year" field.
struct MakeModelParts: Equatable {
    var make: String?
    var model: String?
    var year: Int?
}

/// Best-effort structured split of the free-text "Make · model · year" field.
/// Accepts the suggestion format ("Volvo · V60 CC · 2021") and plain typing
/// ("Volvo V60 2015"). Catalog picks set the structured values directly; this
/// only needs to be right for free text, and it never blocks save.
enum MakeModelParser {
    static func parse(_ text: String) -> MakeModelParts {
        let tokens = text
            .replacingOccurrences(of: "·", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return MakeModelParts() }

        var words = tokens
        var year: Int?
        if let last = words.last, let value = Int(last), (1900...2100).contains(value) {
            year = value
            words.removeLast()
        }
        guard !words.isEmpty else { return MakeModelParts(year: year) }
        let make = words[0]
        let model = words.count > 1 ? words.dropFirst().joined(separator: " ") : nil
        return MakeModelParts(make: make, model: model, year: year)
    }
}

// MARK: - Support

enum AddVehicleSupport {
    /// The currency's symbol, or an empty string when it has no symbol distinct
    /// from its code.
    ///
    /// `NumberFormatter.currencySymbol` with only `currencyCode` set returns the
    /// **code** for most currencies (PLN -> "PLN", CZK -> "CZK", CHF -> "CHF"),
    /// so pairing code and symbol rendered "PLN PLN" on the chips. Asking a
    /// locale that actually uses the currency gets the real glyph, and returning
    /// empty for the genuinely symbol-less cases lets call sites show the code
    /// alone (the artboard: "EUR €", "PLN zł", "CZK Kč", "CHF").
    /// Symbols for the currencies Tankbook targets, matching the artboards
    /// (`ConfirmManual.dc.html`: "EUR €", "PLN zł", "CZK Kč", "CHF").
    ///
    /// An explicit table rather than a `Locale` search: asking `NumberFormatter`
    /// for a symbol with only `currencyCode` set returns the CODE for most of
    /// these, and searching `Locale.availableIdentifiers` for a locale that uses
    /// the currency still missed PLN and RUB. Guessing left the chips reading
    /// "PLN PLN", and would have shown "RUB" where `docs/JOURNEYS.md` promises
    /// a RU locale defaults to ₽.
    private static let knownSymbols: [String: String] = [
        "EUR": "€", "USD": "$", "GBP": "£", "RUB": "₽", "PLN": "zł",
        "CZK": "Kč", "UAH": "₴", "KZT": "₸", "TRY": "₺", "GEL": "₾",
        "SEK": "kr", "NOK": "kr", "DKK": "kr", "HUF": "Ft", "RON": "lei",
        // Deliberately absent: CHF, RSD, BGN and anything else whose symbol IS
        // its code - callers render the code alone rather than doubling it.
    ]

    /// The currency's symbol, or "" when it has none distinct from its code.
    static func currencySymbol(for code: CurrencyCode) -> String {
        if let symbol = knownSymbols[code.rawValue] { return symbol }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.rawValue
        let symbol = formatter.currencySymbol ?? code.rawValue
        return symbol.caseInsensitiveCompare(code.rawValue) == .orderedSame ? "" : symbol
    }

    /// "EUR €", or just "CHF" where the symbol is the code.
    static func currencyLabel(for code: CurrencyCode) -> String {
        let symbol = currencySymbol(for: code)
        return symbol.isEmpty ? code.rawValue : "\(code.rawValue) \(symbol)"
    }

    /// Formats a pre-filled capacity ("71.0" -> "71") for the text field.
    static func capacityText(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    /// The currencies offered in the Home currency menu (the ones the docs name
    /// plus the locales Tankbook targets; everything else stays reachable via
    /// the free-text later, per SCHEMA.md).
    static var currencyOptions: [CurrencyCode] {
        [.eur, .usd, .gbp, .pln, .rub, .uah, .kzt,
         CurrencyCode(rawValue: "BYN")!, .czk, .jpy]
    }
}

extension Powertrain {
    var labelKey: LocalizedStringKey {
        switch self {
        case .ice: "Petrol / Diesel"
        case .hybrid: "Hybrid"
        case .phev: "Plug-in"
        case .ev: "Electric"
        }
    }

    /// Fuel kinds this powertrain can accept, for the chip row.
    var allowedFuelKinds: [FuelKind] {
        switch self {
        case .ice: [.diesel, .petrol95, .petrol98, .lpg, .cng, .e85]
        case .hybrid: [.diesel, .petrol95, .petrol98, .lpg, .cng, .e85]
        case .phev: [.petrol95, .petrol98, .diesel, .electricity]
        case .ev: [.electricity]
        }
    }

    /// Defaults used when switching powertrain leaves no compatible selection.
    var defaultFuelKinds: [FuelKind] {
        switch self {
        case .ice: [.petrol95]
        case .hybrid: [.petrol95]
        case .phev: [.petrol95, .electricity]
        case .ev: [.electricity]
        }
    }
}

extension FuelKind {
    var labelKey: LocalizedStringKey {
        switch self {
        case .diesel: "Diesel"
        case .petrol92: "92"
        case .petrol95: "95"
        case .petrol98: "98"
        case .petrol100: "100"
        case .lpg: "LPG"
        case .cng: "CNG"
        case .e85: "E85"
        case .electricity: "Electricity"
        }
    }
}

extension DistanceUnit {
    var labelKey: LocalizedStringKey {
        switch self {
        case .km: "km"
        case .mi: "mi"
        }
    }
}

extension VolumeUnit {
    var labelKey: LocalizedStringKey {
        switch self {
        case .l: "L"
        case .galUS, .galUK: "gal"
        }
    }
}

extension ConsumptionUnit {
    var labelKey: LocalizedStringKey {
        switch self {
        case .lPer100: "L/100km"
        case .mpgUS: "MPG"
        case .mpgUK: "MPG"
        case .kmPerL: "km/L"
        }
    }
}
