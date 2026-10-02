import Foundation

/// When to ask where a car is kept (docs/SCHEMA.md -> Vehicle.homeCity): once
/// per car, after its first scanned receipt, with the receipt's city as the
/// suggestion. Pure decisions over a small per-car state the app keeps on the
/// device; a car that already has a home city is never asked.
public enum HomeCityQuestion {
    public enum State: Codable, Equatable, Sendable {
        /// Raised and waiting on Home; the dictionary id the receipt suggested.
        case pending(suggestedCityId: Int?)
        /// Answered or dismissed - never asked again for this car.
        case done
    }

    /// The state after a scanned receipt was saved for the car, or nil when
    /// nothing changes (already asked, or the car already has a city).
    public static func afterScannedSave(vehicle: Vehicle, current: State?, receiptLines: [OCRLine],
                                        currency: CurrencyCode?, deviceRegion: String?,
                                        dictionary: CityDictionary) -> State? {
        guard vehicle.homeCity == nil, current == nil else { return nil }
        let hints = [currency.flatMap(country(for:)), deviceRegion].compactMap { $0 }
        let city = ReceiptCityFinder.city(in: receiptLines, dictionary: dictionary, countryHints: hints)
        return .pending(suggestedCityId: city?.id)
    }

    /// The country a currency belongs to, when it belongs to one. The euro and
    /// other shared currencies name none.
    public static func country(for currency: CurrencyCode) -> String? {
        [
            "RUB": "RU", "KZT": "KZ", "BYN": "BY", "UAH": "UA", "PLN": "PL", "CZK": "CZ", "HUF": "HU",
            "RON": "RO", "BGN": "BG", "SEK": "SE", "NOK": "NO", "DKK": "DK", "ISK": "IS", "CHF": "CH",
            "GBP": "GB", "TRY": "TR", "GEL": "GE", "AMD": "AM", "AZN": "AZ", "MDL": "MD", "RSD": "RS",
            "UZS": "UZ", "KGS": "KG",
        ][currency.rawValue]
    }
}
