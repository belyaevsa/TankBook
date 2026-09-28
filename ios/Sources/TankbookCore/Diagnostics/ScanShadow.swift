import Foundation

/// Two routes the beta computes beside a pump capture and records without
/// showing them (docs/CONFIG.md -> the `scanShadow` experiment), so real fills
/// can decide whether either should ship:
///
/// - **The Vision route** (PU.92): the pump parser over the OCR text the capture
///   already read - what a TFT screen's rendered digits give without the
///   segment reader. No extra OCR runs.
/// - **The printed currency** (PU.101): the currency the display prints
///   (`€/L`, `EUR`, `руб`), beside the one the reader was given and the one it
///   closed under - how often the car's currency and the display's disagree.
public struct ScanShadow: Sendable, Equatable {
    public var visionLiters: Double?
    public var visionUnitPrice: Decimal?
    public var visionTotal: Decimal?
    /// Whether the Vision route's three numbers close (`volume x price = total`).
    public var visionCloses: Bool
    public var displayCurrency: String?
    public var readerCurrency: String?
    public var readerClosedUnder: String?

    public static func compute(lines: [OCRLine], bandProvider: (any FuelPriceBandProvider)?,
                               readerCurrency: CurrencyCode?, closedUnder: CurrencyCode?) -> ScanShadow {
        let vision = FuelExtractor(bandProvider: bandProvider).extract(lines: lines, source: .pump, qrAnchor: nil)
        return ScanShadow(visionLiters: vision.liters, visionUnitPrice: vision.unitPrice, visionTotal: vision.total,
                          visionCloses: closes(vision),
                          displayCurrency: CurrencyDetection.detect(in: lines)?.rawValue,
                          readerCurrency: readerCurrency?.rawValue, readerClosedUnder: closedUnder?.rawValue)
    }

    /// Within a cent, as the law's round-or-floor close allows.
    static func closes(_ read: FuelExtraction) -> Bool {
        guard let liters = read.liters, let price = read.unitPrice, let total = read.total else { return false }
        let product = liters * NSDecimalNumber(decimal: price).doubleValue
        return abs(product - NSDecimalNumber(decimal: total).doubleValue) <= 0.011
    }

    /// The record's `shadow` object.
    public var json: [String: Any] {
        func value(_ number: Double?) -> Any { number.map { $0 as Any } ?? NSNull() }
        func value(_ number: Decimal?) -> Any { number.map { NSDecimalNumber(decimal: $0).doubleValue as Any } ?? NSNull() }
        func value(_ text: String?) -> Any { text.map { $0 as Any } ?? NSNull() }
        let vision: [String: Any] = ["liters": value(visionLiters), "unitPrice": value(visionUnitPrice),
                                     "total": value(visionTotal), "closes": visionCloses]
        let currency: [String: Any] = ["display": value(displayCurrency), "reader": value(readerCurrency),
                                       "closedUnder": value(readerClosedUnder)]
        return ["vision": vision, "currency": currency]
    }
}
