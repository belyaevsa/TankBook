import Foundation

// MARK: - The device-ordered currency offer (docs/SCHEMA.md -> Reference data -> Currency offer)

/// Orders the currencies a fill-up/entry row offers. Ordering happens on the
/// device, by the same precedence the station-brand list uses (docs/API.md):
/// the car's home currency first, then the user's own history (most recent
/// first), then the device region's neighbours, then a `detectedCountry` hint
/// the server may send later, then the stable default list. The result IS the
/// "complete list": the chips are its fitted prefix and the More… menu carries
/// the whole thing, so every chip is always reachable again (hard rule 13 -
/// a pick made from the menu is not trapped there).
///
/// This is reference data, never a query and never a network dependency (hard
/// rule 1): every input is local (the vehicle row, the device's own entries,
/// `Locale.current.region`), and the neighbour sets are a bundled table a later
/// remote correction can overlay. A server endpoint returning this list would
/// break hard rule 9 - there is none.
public enum CurrencyOfferBuilder {
    /// The stable tail that keeps the offer complete for a user with no history
    /// and an unknown region: the currencies the app has always offered, in a
    /// stable order. Deduplicated against the higher tiers, so it never
    /// reorders a currency the user has picked (hard rule 13).
    public static let defaultCurrencies: [CurrencyCode] = [
        .eur, .usd, .gbp, .pln, .rub, .uah, .kzt, .byn, .czk, .chf, .jpy
    ]

    /// Builds the complete, ordered offer.
    ///
    /// - `homeCurrency`: the car's own reporting currency; always present and
    ///   always first - the common case must never need More….
    /// - `history`: the currencies the user has actually paid in for this car,
    ///   most recent first (see `CurrencyHistory`).
    /// - `region`: the device region's country code (`Locale.Region` identifier),
    ///   or nil when there is no region.
/// - `hint`: a `detectedCountry` country code from an uncacheable server
///   response. No server carries it yet (docs/API.md, `GET /reference/
///   station-brands`); the slot exists so the field can be added without
///   reshaping this function.
    public static func offer(homeCurrency: CurrencyCode,
                             history: [CurrencyCode] = [],
                             region: String? = nil,
                             hint: String? = nil,
                             catalog: CurrencyRegionCatalog = .bundled) -> [CurrencyCode] {
        var result: [CurrencyCode] = []
        func append(_ codes: [CurrencyCode]) {
            for code in codes where !result.contains(code) {
                result.append(code)
            }
        }
        append([homeCurrency])
        append(history)
        append(catalog.neighbours(for: region))
        append(catalog.neighbours(for: hint))
        append(defaultCurrencies)
        return result
    }
}

/// The region -> neighbouring-currencies table (docs/SCHEMA.md -> Reference
/// data -> Currency offer). Each row leads with the country's own currency,
/// then the currencies a driver in that country is plausibly handed across the
/// border. Bundled reference data: a corrected set replaces a row wholesale,
/// and `applying(_:)` is the seam a future remote correction lands in.
public struct CurrencyRegionCatalog: Sendable, Equatable {
    /// Explicitly curated rows, keyed by ISO 3166-1 alpha-2 country code.
    public let rows: [String: [CurrencyCode]]
    /// Eurozone members sharing one default row; curated as a set so a
    /// correction that adds a member does not reshape the table.
    public let eurozone: Set<String>

    /// The single default Eurozone row (docs/SCHEMA.md: the Eurozone -> EUR,
    /// PLN, CZK): the currency every member shares, then the two neighbour
    /// currencies the app's markets most often meet at the pump.
    public static let eurozoneDefault: [CurrencyCode] = [.eur, .pln, .czk]

    /// The table shipped in the bundle. Corrected later by remote config, never
    /// by a server endpoint.
    public static let bundled = CurrencyRegionCatalog(
        rows: [
            "RU": [.rub, .kzt, .byn],
            "KZ": [.kzt, .rub, .kgs, .uzs],
            "BY": [.byn, .rub],
            "UA": [.uah, .rub, .pln],
            "PL": [.pln, .eur, .czk],
            "CZ": [.czk, .eur, .pln],
            "CH": [.chf, .eur],
            "US": [.usd, .eur],
            "GB": [.gbp, .eur],
            "JP": [.jpy, .usd]
        ],
        eurozone: [
            "AT", "BE", "CY", "EE", "FI", "FR", "DE", "GR", "IE", "IT",
            "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI", "ES", "HR"
        ])

    public init(rows: [String: [CurrencyCode]], eurozone: Set<String>) {
        self.rows = rows
        self.eurozone = eurozone
    }

    /// The ordered neighbour set for a country code, or empty for an unknown
    /// one. Unknown is not an error: the offer's stable default keeps the row
    /// non-empty (docs/SCHEMA.md -> Currency offer).
    public func neighbours(for country: String?) -> [CurrencyCode] {
        guard let country else { return [] }
        let code = country.uppercased()
        if let row = rows[code] { return row }
        if eurozone.contains(code) { return Self.eurozoneDefault }
        return []
    }

    /// A copy with the given rows overlaid - the shape a future remote
    /// correction (docs/CONFIG.md) would apply. Only ever corrects the table;
    /// it never reaches a currency the user has picked, because a user pick
    /// lives in `history`, which outranks every row here.
    public func applying(_ overrides: [String: [CurrencyCode]]) -> CurrencyRegionCatalog {
        var merged = rows
        for (country, row) in overrides {
            merged[country.uppercased()] = row
        }
        return CurrencyRegionCatalog(rows: merged, eurozone: eurozone)
    }
}

/// Derives the "user's own history" tier from the car's entries
/// (docs/SCHEMA.md -> Currency offer): the distinct original currencies of the
/// entries' money pairs, most recent first. There is no separate recency store;
/// the entries themselves are the history, so a currency a user chose once
/// stays offered - no locale change or curation can reorder it away (hard
/// rule 13). Home-currency entries are left in (they deduplicate against the
/// home tier); money-less entries carry no currency.
public enum CurrencyHistory {
    public static func recentCurrencies(in entries: [any Entry]) -> [CurrencyCode] {
        struct Usage {
            let currency: CurrencyCode
            let date: Date
            let created: Date
        }
        let ordered = entries
            .compactMap { entry -> Usage? in
                guard let currency = entry.money?.currency else { return nil }
                return Usage(currency: currency, date: entry.date, created: entry.createdAt)
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.created > rhs.created
            }
        var seen: [CurrencyCode] = []
        for item in ordered where !seen.contains(item.currency) {
            seen.append(item.currency)
        }
        return seen
    }
}
