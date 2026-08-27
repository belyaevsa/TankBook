import Foundation

/// ISO-4217 currency code wrapper. Stored uppercase, exactly three letters.
/// Names follow docs/SCHEMA.md exactly - canonical across Swift, C# and SQL.
public struct CurrencyCode: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    /// Creates a code from any casing; fails unless the value is three letters.
    public init?(rawValue: String) {
        let normalized = rawValue.uppercased()
        guard normalized.count == 3,
              normalized.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }
        self.rawValue = normalized
    }

    /// Standard minor units (decimal places) for this currency.
    public var minorUnits: Int {
        switch rawValue {
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 3
        case "BIF", "CLP", "CVE", "GNF", "ISK", "JPY", "KRW", "PYG",
             "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF":
            return 0
        default:
            return 2
        }
    }
}

extension CurrencyCode {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let code = CurrencyCode(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-4217 code '\(raw)'"
            )
        }
        self = code
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension CurrencyCode {
    static let eur = CurrencyCode(rawValue: "EUR")!
    static let usd = CurrencyCode(rawValue: "USD")!
    static let gbp = CurrencyCode(rawValue: "GBP")!
    static let pln = CurrencyCode(rawValue: "PLN")!
    static let rub = CurrencyCode(rawValue: "RUB")!
    static let uah = CurrencyCode(rawValue: "UAH")!
    static let kzt = CurrencyCode(rawValue: "KZT")!
    static let jpy = CurrencyCode(rawValue: "JPY")!
    static let czk = CurrencyCode(rawValue: "CZK")!
}

/// Who supplied an exchange rate (docs/SCHEMA.md, Money.rateSource).
public enum RateSource: String, Codable, Sendable, CaseIterable {
    case ecb
    case cis
    case manual
}

/// An exchange-rate snapshot: the rate and the day it applied. `rateDate` is
/// the ENTRY date - the day the purchase happened - never "today"
/// (docs/SCHEMA.md, Money conversion semantics).
public struct RateSnapshot: Codable, Hashable, Sendable {
    public var rate: Decimal
    public var rateDate: Date
    public var source: RateSource

    public init(rate: Decimal, rateDate: Date, source: RateSource) {
        self.rate = rate
        self.rateDate = rateDate
        self.source = source
    }
}

/// Money is always a pair: the amount as paid plus its conversion into the
/// vehicle's home currency with the rate snapshot. Amounts are `Decimal`,
/// never `Double` (docs/SCHEMA.md, Money).
public struct Money: Codable, Hashable, Sendable {
    public private(set) var amount: Decimal
    public private(set) var currency: CurrencyCode
    public private(set) var homeAmount: Decimal?
    public private(set) var homeCurrency: CurrencyCode
    public private(set) var rate: Decimal?
    public private(set) var rateDate: Date?
    public private(set) var rateSource: RateSource

    /// True once a conversion snapshot is written; snapshots are immutable.
    public var hasSnapshot: Bool { homeAmount != nil }

    /// True while the conversion is still waiting on a rate (rate-pending, F3/F9).
    public var isRatePending: Bool { !hasSnapshot }

    /// Creates money in its original currency. When the original currency equals
    /// the home currency the pair is snapshotted immediately at rate 1.
    public init(amount: Decimal, currency: CurrencyCode, homeCurrency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
        self.homeCurrency = homeCurrency
        self.rateSource = .ecb
        self.rate = nil
        self.rateDate = nil
        if currency == homeCurrency {
            self.homeAmount = amount
            self.rate = Decimal(1)
        } else {
            self.homeAmount = nil
        }
    }

    /// Applies an exchange-rate snapshot. Fill-blanks-only: a value that already
    /// carries a snapshot is returned unchanged - later rate feeds never touch
    /// it, and `rateDate` is taken from the snapshot (the entry date), never today.
    /// `homeAmount = amount / rate`; the rate is ORIGINAL per HOME.
    public func converted(using snapshot: RateSnapshot) -> Money {
        guard homeAmount == nil else { return self }
        guard currency != homeCurrency else { return self }
        guard snapshot.rate > 0 else { return self }
        var copy = self
        copy.homeAmount = (amount / snapshot.rate).rounded(decimalPlaces: homeCurrency.minorUnits)
        copy.rate = snapshot.rate
        copy.rateDate = snapshot.rateDate
        copy.rateSource = snapshot.source
        return copy
    }

    /// Applies a USER-supplied rate for the entry's date (hard rule 13, F9).
    /// This is the manual override path and is deliberately separate from
    /// `converted(using:)`: the feed path fills a blank and never touches a
    /// written snapshot, but a manual rate is the user's decision and must
    /// REPLACE whatever the feed wrote - it sets `rateSource = .manual`. The
    /// resulting snapshot then survives later feed backfill, because
    /// `converted(using:)` never rewrites a written `homeAmount`.
    public func applyingManualRate(_ rate: Decimal, on date: Date) -> Money {
        guard currency != homeCurrency else { return self }
        guard rate > 0 else { return self }
        var copy = self
        copy.homeAmount = (amount / rate).rounded(decimalPlaces: homeCurrency.minorUnits)
        copy.rate = rate
        copy.rateDate = date
        copy.rateSource = .manual
        return copy
    }

    /// A copy with `amount` replaced. Editing the amount clears any existing
    /// snapshot for re-conversion; same-currency money stays snapshotted at
    /// rate 1 with `homeAmount` following `amount`.
    public func replacingAmount(_ newAmount: Decimal) -> Money {
        var copy = self
        copy.amount = newAmount
        copy.resetSnapshotForEdit()
        return copy
    }

    /// A copy with `currency` replaced. Editing the currency clears any existing
    /// snapshot for re-conversion.
    public func replacingCurrency(_ newCurrency: CurrencyCode) -> Money {
        var copy = self
        copy.currency = newCurrency
        copy.resetSnapshotForEdit()
        return copy
    }

    private mutating func resetSnapshotForEdit() {
        if currency == homeCurrency {
            homeAmount = amount
            rate = Decimal(1)
        } else {
            homeAmount = nil
            rate = nil
        }
        rateDate = nil
        rateSource = .ecb
    }
}

public extension Decimal {
    /// Rounds to `places` decimal places (`.plain` = half away from zero).
    func rounded(decimalPlaces places: Int, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var result = Decimal()
        var copy = self
        NSDecimalRound(&result, &copy, places, roundingMode)
        return result
    }
}

extension Money {
    /// Reconstructs a money pair from a stored payload *exactly*, without
    /// recomputing the snapshot (`homeAmount` is not `amount / rate` re-derived;
    /// the stored value is the authority). Used by the payload decoder
    /// (docs/SCHEMA.md, Money - snapshots are immutable).
    init(amount: Decimal, currency: CurrencyCode,
         homeAmount: Decimal?, homeCurrency: CurrencyCode,
         rate: Decimal?, rateDate: Date?, rateSource: RateSource) {
        self.amount = amount
        self.currency = currency
        self.homeAmount = homeAmount
        self.homeCurrency = homeCurrency
        self.rate = rate
        self.rateDate = rateDate
        self.rateSource = rateSource
    }
}
