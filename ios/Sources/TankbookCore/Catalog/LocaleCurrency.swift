import Foundation

/// Locale-driven currency defaulting for the Add-car screen. Home currency
/// pre-fills from the device locale (docs/JOURNEYS.md, Add car: "home currency
/// pre-filled from locale"); the RU case defaults to the rouble.
public enum LocaleCurrency {
    /// The currency most users in `locale`'s region expect. Explicit CIS/EU
    /// mappings first (these are the markets Tankbook targets), then the
    /// locale's own currency identifier, then EUR as the neutral default.
    public static func defaultCurrency(for locale: Locale) -> CurrencyCode {
        switch locale.region?.identifier.uppercased() {
        case "RU": return CurrencyCode(rawValue: "RUB")!
        case "UA": return CurrencyCode(rawValue: "UAH")!
        case "KZ": return CurrencyCode(rawValue: "KZT")!
        case "BY": return CurrencyCode(rawValue: "BYN")!
        case "PL": return .pln
        case "US": return .usd
        case "GB": return .gbp
        case "JP": return .jpy
        case "CZ": return .czk
        default:
            if let identifier = locale.currency?.identifier,
               let code = CurrencyCode(rawValue: identifier) {
                return code
            }
            return .eur
        }
    }
}
