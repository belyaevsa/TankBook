import Foundation

/// The currency a pump photo is read under. The law's decimal conventions and
/// the price band both key off it, so a wrong currency makes the reader refuse
/// a display it would otherwise read (docs/EXTRACTION.md -> "The currency the
/// reader is given").
///
/// The car's home currency comes first: it is what the user said they pay in,
/// and it does not change when the phone's region is set to another country.
/// The phone's region is the fallback for a capture with no car.
public enum PumpReaderCurrency {
    public static func choose(homeCurrency: CurrencyCode?, region: Locale) -> CurrencyCode? {
        homeCurrency ?? region.currency.flatMap { CurrencyCode(rawValue: $0.identifier) }
    }
}
