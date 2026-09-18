import Foundation

// MARK: - Price per unit by station brand (docs/JOURNEYS.md J8: "price-per-liter
// line per station brand - 'Shell costs you 4% more than Neste'")

/// One brand's price history on this car, in the car's home currency.
public struct BrandPriceSeries: Equatable, Sendable {
    /// The station's brand, or its name when no brand is recorded - a
    /// by-hand station is its own "brand" rather than an unnamed bucket.
    public let brand: String
    /// The fills' home unit prices, oldest first.
    public let series: [TrendPoint]
    /// The plain mean of `series` - a comparison figure, never a headline.
    public let meanPrice: Double

    public var fillCount: Int { series.count }
}

/// The sentence-shaped answer over the brands: the dearest against the
/// cheapest, as a rounded percent.
public struct BrandPriceGap: Equatable, Sendable {
    public let dearest: String
    public let cheapest: String
    /// Rounded to a whole percent; `0` means "about the same".
    public let percent: Int
}

public enum BrandPrices {
    /// Fills a brand needs before its figure is shown - one fill is a price,
    /// not a pattern.
    public static let minimumFillsPerBrand = 2
    /// The comparison's window: a year, so a summer of one brand and a winter
    /// of another still meet.
    public static let windowDays = 365

    /// The brands with enough fills in the window, cheapest first. Fills
    /// without a station, or whose home price is unknown (rate pending), are
    /// left out - never counted at a guessed price.
    public static func series(entries: [any Entry], stations: [Station],
                              vehicleHome: CurrencyCode, asOf: Date) -> [BrandPriceSeries] {
        let start = asOf.addingTimeInterval(-Double(windowDays) * 86_400)
        let brandByStation = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0.brand ?? $0.name) })
        var pointsByBrand: [String: [TrendPoint]] = [:]
        for entry in entries {
            guard let fill = entry as? FillUp, fill.date >= start, fill.date <= asOf,
                  let stationId = fill.stationId, let brand = brandByStation[stationId],
                  let price = HomeStats.unitPriceFigure(of: fill, vehicleHome: vehicleHome) else { continue }
            pointsByBrand[brand, default: []].append(
                TrendPoint(date: fill.date, value: (price.amount as NSDecimalNumber).doubleValue))
        }
        return pointsByBrand
            .filter { $0.value.count >= minimumFillsPerBrand }
            .map { brand, points in
                let sorted = points.sorted { $0.date < $1.date }
                let mean = sorted.reduce(0) { $0 + $1.value } / Double(sorted.count)
                return BrandPriceSeries(brand: brand, series: sorted, meanPrice: mean)
            }
            .sorted { $0.meanPrice < $1.meanPrice }
    }

    /// The dearest brand against the cheapest; `nil` with fewer than two brands.
    public static func gap(_ series: [BrandPriceSeries]) -> BrandPriceGap? {
        guard let cheapest = series.first, let dearest = series.last,
              series.count >= 2, cheapest.meanPrice > 0 else { return nil }
        let percent = Int(((dearest.meanPrice - cheapest.meanPrice) / cheapest.meanPrice * 100).rounded())
        return BrandPriceGap(dearest: dearest.brand, cheapest: cheapest.brand, percent: percent)
    }
}
