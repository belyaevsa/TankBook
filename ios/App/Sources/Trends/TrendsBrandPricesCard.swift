import SwiftUI
import TankbookCore

/// Price per unit by station brand (docs/JOURNEYS.md J8: "price-per-liter
/// line per station brand"): one row per brand, cheapest first, each with its
/// own price line, and the sentence the journey names - "Shell costs you 4%
/// more than Neste". Rendered only when two brands have two fills each
/// (`TrendsStats.brandPrices` is empty otherwise), so the card never compares
/// a brand against nothing.
struct TrendsBrandPricesCard: View {
    let stats: TrendsStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ManualFillUpUnitCopy.priceByBrandTitle(for: stats.vehicle.units.volume))
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkSoft)
            ForEach(stats.brandPrices, id: \.brand) { brand in
                row(brand)
            }
            if let gap = stats.brandPriceGap {
                Text(Self.gapSentence(gap))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trendsBrandPriceGap")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .formCard()
        .accessibilityIdentifier("trendsBrandPricesCard")
    }

    private func row(_ brand: BrandPriceSeries) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(brand.brand)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text(L10n.fillsCount(brand.fillCount))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 8)
            Sparkline(values: brand.series.map { .some($0.value) }, color: Theme.Palette.inkSoft)
                .frame(width: 72, height: 22)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(HomeFormat.unitPriceValue(Decimal(brand.meanPrice),
                                               volumeUnit: stats.vehicle.units.volume))
                    .font(.custom(AppFonts.dinAlternateBold, size: 17))
                    .foregroundStyle(Theme.Palette.ink)
                    .monospacedDigit()
                Text(AddVehicleSupport.moneySymbol(for: stats.vehicle.homeCurrency))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        // One spoken element per row ("Neste, 4 fills, 1.639 €"); the card's
        // identifier covers the rows, so they carry none of their own.
        .accessibilityElement(children: .combine)
    }

    /// "Shell costs you 4% more than Neste", or the about-the-same sentence
    /// when the rounded gap is zero - one full phrase per language, the
    /// brands are data.
    static func gapSentence(_ gap: BrandPriceGap) -> String {
        if gap.percent == 0 {
            return String(format: L10n.localize("%1$@ and %2$@ cost you about the same"),
                          gap.dearest, gap.cheapest)
        }
        return String(format: L10n.localize("%1$@ costs you %2$@%% more than %3$@"),
                      gap.dearest, "\(gap.percent)", gap.cheapest)
    }
}

extension L10n {
    /// "4 fills" - the per-brand price row's count, real plural rules.
    static func fillsCount(_ count: Int) -> String {
        String(localized: "\(count) fills")
    }
}
