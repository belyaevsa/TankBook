import Foundation

// MARK: - Relevance ordering, on the device (docs/API.md -> "Relevance is ordered on the DEVICE")

/// Orders the vocabulary for a picker: the receipt in hand first, then the
/// brands the user already fuels at, then the device region's, then the
/// server's cold-start hint, then the rest - each tier alphabetical. Every
/// signal is optional and absent-able; with none, the list is alphabetical.
/// Only the device holds the history (hard rules 1 and 9), and a hint is a
/// default input that never outranks it (hard rule 13).
public enum StationBrandOrdering {
    public struct Signals: Sendable, Equatable {
        /// The country the capture in hand implies (its currency, script, VAT
        /// line) - the strongest present-tense signal.
        public var receiptCountry: String?
        /// Brand ids of the stations the user already has.
        public var usedBrandIDs: Set<String>
        /// The device region (`Locale.current.region`).
        public var deviceRegion: String?
        /// The server's per-request cold-start hint, if one arrived.
        public var detectedCountry: String?

        public init(receiptCountry: String? = nil, usedBrandIDs: Set<String> = [],
                    deviceRegion: String? = nil, detectedCountry: String? = nil) {
            self.receiptCountry = receiptCountry
            self.usedBrandIDs = usedBrandIDs
            self.deviceRegion = deviceRegion
            self.detectedCountry = detectedCountry
        }
    }

    public static func ordered(_ brands: [StationBrand], signals: Signals) -> [StationBrand] {
        func tier(_ brand: StationBrand) -> Int {
            if let country = signals.receiptCountry, brand.country == country.uppercased() { return 0 }
            if signals.usedBrandIDs.contains(brand.id) { return 1 }
            if let region = signals.deviceRegion, brand.country == region.uppercased() { return 2 }
            if let hint = signals.detectedCountry, brand.country == hint.uppercased() { return 3 }
            return 4
        }
        return brands.sorted { lhs, rhs in
            let left = tier(lhs), right = tier(rhs)
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The country a capture's currency implies, for currencies one country
    /// uses; nil for a shared one (EUR, USD abroad) - no signal beats a wrong
    /// one.
    public static func country(forCurrency currency: CurrencyCode) -> String? {
        Self.singleCountryCurrencies[currency.rawValue]
    }

    /// Currencies one country uses; a shared one (EUR, USD abroad) is absent
    /// on purpose - no signal beats a wrong one.
    private static let singleCountryCurrencies: [String: String] = [
        "RUB": "RU", "KZT": "KZ", "BYN": "BY", "UAH": "UA", "GBP": "GB", "PLN": "PL",
        "CZK": "CZ", "HUF": "HU", "RON": "RO", "SEK": "SE", "NOK": "NO", "DKK": "DK",
        "CHF": "CH", "CAD": "CA", "MXN": "MX", "AZN": "AZ", "GEL": "GE", "AMD": "AM",
        "UZS": "UZ", "KGS": "KG"
    ]

    /// The signals a picker has: the brands the user's stations already carry
    /// (matched back to ids by name), the capture's currency when there is
    /// one, the device region and the last server hint.
    public static func signals(stations: [Station], brands: [StationBrand],
                               currency: CurrencyCode? = nil,
                               deviceRegion: String? = Locale.current.region?.identifier,
                               detectedCountry: String? = StationBrandRegistry.detectedCountry) -> Signals {
        let used = Set(stations.compactMap { station -> String? in
            guard let brand = station.brand else { return nil }
            return brands.first { $0.name == brand }?.id
        })
        return Signals(receiptCountry: currency.flatMap(country(forCurrency:)),
                       usedBrandIDs: used, deviceRegion: deviceRegion, detectedCountry: detectedCountry)
    }
}
