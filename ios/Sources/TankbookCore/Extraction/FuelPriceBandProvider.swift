import Foundation

// MARK: - Ladder step 3: the user's own price history

/// The resolution ladder's step 3 (docs/SCHEMA.md -> Fuel price bands): the
/// median unit price of the vehicle's most recent fill-ups in a currency. It is
/// preferred over the curated band because it needs no network (hard rule 1),
/// tracks inflation, and follows the user's own grade and stations
/// automatically. It is a SNAPSHOT taken when the provider is built, so a
/// capture running against the same fill-up it is about to write never sees
/// itself.
public struct FillUpHistory: Sendable, Equatable {
    /// How many recent fill-ups feed the median (docs/SCHEMA.md: "the last ~10").
    public static let window = 10
    /// Below this many priced fill-ups in a currency there is no history to
    /// trust: a single fill-up is a point, not a distribution, and one grade
    /// switch (95 -> 100) would read as a 30% price jump.
    public static let minimumSamples = 2

    private let samples: [Sample]

    struct Sample: Sendable, Equatable {
        let date: Date
        let currency: CurrencyCode
        let unitPrice: Double
    }

    public init(fillUps: [FillUp]) {
        self.samples = fillUps
            .compactMap { fill -> Sample? in
                guard let unitPrice = fill.unitPrice, let money = fill.money else { return nil }
                return Sample(date: fill.date, currency: money.currency,
                              unitPrice: NSDecimalNumber(decimal: unitPrice).doubleValue)
            }
            .sorted { $0.date > $1.date }
    }

    /// The median unit price of the last ~`window` fill-ups in `currency`, or
    /// nil when there are fewer than `minimumSamples`. `fuelKind` is accepted
    /// for the protocol's symmetry but not used: the schema keys history on
    /// currency, and the median over a user's mixed-grade fills IS their usual
    /// grade.
    public func historicalPrice(currency: CurrencyCode?, fuelKind: FuelKind?) -> Double? {
        guard let currency else { return nil }
        let recent = samples
            .filter { $0.currency == currency }
            .prefix(Self.window)
        guard recent.count >= Self.minimumSamples else { return nil }
        return Self.median(recent.map(\.unitPrice))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

// MARK: - The default provider (history, then band)

/// The provider the app injects: step 3 (user history) first, then step 4 (the
/// curated pack). `resolveUnmarked` already walks those two steps in order
/// (`FuelExtractor.swift`); this type just supplies both halves of the seam.
public struct DefaultFuelPriceBandProvider: FuelPriceBandProvider {
    public let pack: FuelPriceBandPack
    public let history: FillUpHistory?

    public init(pack: FuelPriceBandPack, history: FillUpHistory? = nil) {
        self.pack = pack
        self.history = history
    }

    public func band(currency: CurrencyCode?, fuelKind: FuelKind?, date: Date?) -> FuelPriceBand? {
        guard let currency, let fuelKind else { return nil }
        return pack.band(currency: currency, fuelKind: fuelKind, date: date)
    }

    public func historicalPrice(currency: CurrencyCode?, fuelKind: FuelKind?) -> Double? {
        history?.historicalPrice(currency: currency, fuelKind: fuelKind)
    }

    public func currencyBand(currency: CurrencyCode?) -> FuelPriceBand? {
        guard let currency else { return nil }
        return pack.currencyBand(currency: currency)
    }
}
