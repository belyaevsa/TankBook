import Foundation

/// A coarse plausible price-per-litre range, keyed by currency, fuel kind and
/// period (docs/SCHEMA.md -> Reference data -> Fuel price bands). It exists for
/// one job: deciding which of two numbers on a receipt is the price and which
/// is the volume. It is never shown as a market rate and never rejects a fill.
public struct FuelPriceBand: Sendable, Equatable {
    public let low: Double
    public let high: Double

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }

    public func contains(_ price: Double) -> Bool {
        price >= low && price <= high
    }
}

/// Injected seam for the resolution ladder's steps 3 (user price history) and
/// 4 (curated band). The band pack and the history store are P5; only the
/// interface is defined here so the ladder is testable with a stub provider.
public protocol FuelPriceBandProvider: Sendable {
    /// Step 4: the curated plausible range for this currency/fuel/date, or nil
    /// when no band is known. Bands rank, never veto (docs/SCHEMA.md). Currency
    /// is optional because OCR does not always yield one.
    func band(currency: CurrencyCode?, fuelKind: FuelKind?, date: Date?) -> FuelPriceBand?

    /// Step 3: the user's historical median unit price for this currency and
    /// fuel, or nil when there is no history. Needs no network (hard rule 1).
    func historicalPrice(currency: CurrencyCode?, fuelKind: FuelKind?) -> Double?

    /// The currency-wide band for the pump scale search (B2). A pump names a
    /// currency but never a fuel kind, so the family-keyed `band` is unavailable;
    /// this is the union across families/eras (see
    /// `FuelPriceBandPack.currencyBand`).
    func currencyBand(currency: CurrencyCode?) -> FuelPriceBand?
}

extension FuelPriceBandProvider {
    /// Default: no currency-wide band. Receipt-only providers and test stubs
    /// need not supply one - the pump path then abstains on scale (a missing pin
    /// is a refusal, never a guess).
    func currencyBand(currency: CurrencyCode?) -> FuelPriceBand? { nil }
}
