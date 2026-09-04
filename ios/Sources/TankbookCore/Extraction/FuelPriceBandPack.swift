import Foundation

// MARK: - The fuel-price band pack (docs/SCHEMA.md -> Fuel price bands)

// The resolution ladder's step 4 (docs/SCHEMA.md): a coarse, curated,
// per-country/currency/fuel-kind/period range for "price per litre". It exists
// for one job - deciding which of two numbers on an unmarked receipt is the
// price and which is the volume. It is never shown as a market rate and never
// rejects a fill-up (bands rank, never veto). It rides the same bundled-seed
// mechanism as the vehicle catalog and the exchange rates: the pack ships in
// the app bundle so day-one offline capture has a fallback, and the download
// path (`GET /reference/fuel-price-bands`) is a later task.

/// The band's fuel key. The ladder keys bands by fuel FAMILY, not the specific
/// octane grade: petrol grades (92/95/98/100) share one tank and one price
/// scale, diesel is a sibling scale, and LPG runs roughly a third of petrol -
/// which is exactly the difference a band must not blur (a petrol band rejects
/// the correct answer for an LPG fill, docs/SCHEMA.md).
public enum FuelBandFamily: String, Codable, Sendable, CaseIterable {
    case petrol
    case diesel
    case lpg
}

extension FuelKind {
    /// The band family this kind belongs to, or nil when the kind is not given
    /// a band. CNG is metered per m3 and electricity per kWh - a litre band
    /// would be meaningless; e85 is per-litre but priced BELOW petrol in some
    /// markets (a petrol floor would reject the correct answer, the same swap
    /// the LPG key prevents) - so for these, no band is offered rather than a
    /// wrong one.
    public var bandFamily: FuelBandFamily? {
        switch self {
        case .petrol92, .petrol95, .petrol98, .petrol100: return .petrol
        case .diesel: return .diesel
        case .lpg: return .lpg
        case .cng, .e85, .electricity: return nil
        }
    }
}

/// One curated band row. `country` is stored for schema fidelity (the server
/// table is keyed by it) and for the future server pack's shape, but the
/// CLIENT disambiguates on `currency` - OCR never yields a country, and several
/// countries share a currency (EUR). The four key columns are all load-bearing
/// (docs/SCHEMA.md): fuel kind (LPG vs petrol), period (48.80 in 2022 vs 450 in
/// 2026), currency (1.869 EUR vs 205 RUB are both ordinary).
public struct FuelPriceBandEntry: Equatable, Sendable {
    public let country: String
    public let currency: CurrencyCode
    public let fuelKind: FuelBandFamily
    public let periodStart: Date
    public let low: Double
    public let high: Double
    public let source: String
    public let note: String?

    public init(country: String, currency: CurrencyCode, fuelKind: FuelBandFamily,
                periodStart: Date, low: Double, high: Double, source: String, note: String?) {
        self.country = country
        self.currency = currency
        self.fuelKind = fuelKind
        self.periodStart = periodStart
        self.low = low
        self.high = high
        self.source = source
        self.note = note
    }
}

/// The loaded band table. `band(currency:fuelKind:date:)` picks the row whose
/// (currency, family) match and whose `periodStart` is the greatest not after
/// the receipt's own date - never today's (a band matched to today would
/// misread every imported backlog, docs/SCHEMA.md).
public struct FuelPriceBandPack: Equatable, Sendable {
    public let entries: [FuelPriceBandEntry]

    public init(entries: [FuelPriceBandEntry]) {
        self.entries = entries
    }

    /// Step 4's lookup. Returns nil when the currency or fuel kind is unknown
    /// (an unknown fuel kind must never fall back to a petrol band - that is
    /// precisely the swap `receipt-012` proves the fuel-kind key prevents), or
    /// when no band's period covers the date.
    public func band(currency: CurrencyCode, fuelKind: FuelKind, date: Date?) -> FuelPriceBand? {
        guard let family = fuelKind.bandFamily else { return nil }
        return band(currency: currency, family: family, date: date)
    }

    public func band(currency: CurrencyCode, family: FuelBandFamily, date: Date?) -> FuelPriceBand? {
        let candidates = entries.filter { $0.currency == currency && $0.fuelKind == family }
        guard !candidates.isEmpty else { return nil }
        let chosen: FuelPriceBandEntry?
        if let date {
            chosen = candidates
                .filter { $0.periodStart <= date }
                .max(by: { $0.periodStart < $1.periodStart })
        } else {
            // No receipt date: use the most recent period's band. A nil date
            // usually means a degraded/undated print, and the most recent band
            // is the widest, so this errs toward abstaining rather than a swap.
            chosen = candidates.max(by: { $0.periodStart < $1.periodStart })
        }
        return chosen.map { FuelPriceBand(low: $0.low, high: $0.high) }
    }
}

// MARK: - Bundled seed pack

/// The seed pack envelope: a version plus the rows it curates.
struct FuelPriceBandSeed: Codable {
    let packVersion: Int
    let bands: [Row]

    struct Row: Codable {
        let country: String
        let currency: String
        let fuelKind: String
        let periodStart: String
        let low: Double
        let high: Double
        let source: String
        let note: String?
    }
}

/// Errors from loading a seed pack. A malformed pack is rejected WHOLE - the
/// same discipline as the vehicle catalog and the exchange rates
/// (docs/SYNC.md -> Reference data).
public enum FuelPriceBandError: Error, Equatable {
    case bundleMissing
    case invalidCurrency(String)
    case invalidFuelKind(String)
    case invalidPeriodStart(String)
}

/// Loads the bundled seed pack (docs/SCHEMA.md -> Fuel price bands: shipped as
/// a bundled seed so day-one offline capture has a fallback).
public enum FuelPriceBandStore {
    public static let bundledResourceName = "FuelPriceBands.seed"
    public static let bundledExtension = "json"

    public static func bundledPack() throws -> FuelPriceBandPack {
        guard let url = Bundle.module.url(forResource: bundledResourceName,
                                          withExtension: bundledExtension) else {
            throw FuelPriceBandError.bundleMissing
        }
        return try pack(at: url)
    }

    public static func pack(at url: URL) throws -> FuelPriceBandPack {
        try decode(data: Data(contentsOf: url))
    }

    public static func decode(data: Data) throws -> FuelPriceBandPack {
        let seed = try JSONDecoder().decode(FuelPriceBandSeed.self, from: data)
        return FuelPriceBandPack(entries: try seed.bands.map { row in
            guard let currency = CurrencyCode(rawValue: row.currency) else {
                throw FuelPriceBandError.invalidCurrency(row.currency)
            }
            guard let family = FuelBandFamily(rawValue: row.fuelKind) else {
                throw FuelPriceBandError.invalidFuelKind(row.fuelKind)
            }
            guard let start = Self.day(row.periodStart) else {
                throw FuelPriceBandError.invalidPeriodStart(row.periodStart)
            }
            return FuelPriceBandEntry(country: row.country, currency: currency,
                                      fuelKind: family, periodStart: start,
                                      low: row.low, high: row.high,
                                      source: row.source, note: row.note)
        })
    }

    /// Parses a `YYYY-MM-DD` period start into a Gregorian start-of-day date.
    private static func day(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: year, month: month, day: day))
    }
}
