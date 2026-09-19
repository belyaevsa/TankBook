import SwiftUI
import TankbookCore

// MARK: - The fill pattern card (RV.120, docs/JOURNEYS.md J8)

/// Under the vitals: how far between fills, how often, how far the tank goes,
/// what the month will cost - the answers a driver standing at a pump wants.
/// Every figure is `HomeStats.fillPattern`'s (derived in core, hard rule 2);
/// a figure the data cannot yield is OMITTED - never zeroed, never dashed -
/// and the whole card is absent under the consumption floor. The forecast is
/// a prediction and reads as one ("≈", "on pace"); the range names the tank
/// it was built on, which the user's own fills had to corroborate first.
struct HomeFillPatternCard: View {
    let pattern: FillPattern
    let vehicle: Vehicle

    var body: some View {
        if !pattern.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // The identifier sits on the eyebrow, not the container: a
                // container id would swallow the rows' own ids.
                Text("Fill pattern")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("homeFillPatternCard")
                if let between = HomeFillPatternFormat.betweenFills(pattern, vehicle: vehicle) {
                    row(title: L10n.localize("Between fills"), value: between.value, detail: between.detail,
                        identifier: "homeFillPatternBetween")
                }
                if let range = pattern.rangeLeftKm, let capacity = vehicle.tankCapacityL {
                    row(title: L10n.localize("Range left"),
                        value: HomeFillPatternFormat.distance(range, vehicle: vehicle),
                        detail: String(format: L10n.localize("on a %@ tank"),
                                       HomeFillPatternFormat.capacity(capacity, vehicle: vehicle)),
                        identifier: "homeFillPatternRange")
                }
                if let forecast = pattern.monthForecast {
                    row(title: L10n.localize("This month, on pace"),
                        value: String(format: L10n.localize("≈ %@"),
                                      HomeFormat.spend(forecast.amount,
                                                       symbol: AddVehicleSupport.moneySymbol(for: forecast.currency))),
                        detail: String(localized: "after \(forecast.daysElapsed) days"),
                        identifier: "homeFillPatternForecast")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.cardPadding)
            .formCard()
        }
    }

    private func row(title: String, value: String, detail: String?, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.custom(AppFonts.dinAlternateBold, size: 16))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier(identifier)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
        }
    }
}

enum HomeFillPatternFormat {
    /// "500 km" with "every 10 days" beneath - the spacing's two halves, each
    /// a whole localised phrase; absent when neither exists.
    static func betweenFills(_ pattern: FillPattern, vehicle: Vehicle) -> (value: String, detail: String?)? {
        if let km = pattern.kmBetweenFills {
            let detail = pattern.daysBetweenFills.map {
                String(format: L10n.localize("Every %@ days"), ManualFillUpFormat.decimal($0, fractionDigits: 1))
            }
            return (distance(km, vehicle: vehicle), detail)
        }
        if let days = pattern.daysBetweenFills {
            let figure = ManualFillUpFormat.decimal(days, fractionDigits: 1)
            return (String(format: L10n.localize("Every %@ days"), figure), nil)
        }
        return nil
    }

    static func distance(_ km: Int, vehicle: Vehicle) -> String {
        "\(OdometerFormat.grouped(km)) \(L10n.distanceUnit(vehicle.units.distance))"
    }

    static func capacity(_ litres: Double, vehicle: Vehicle) -> String {
        let display = ManualFillUpMath.displayVolume(from: litres, unit: vehicle.units.volume)
        return "\(ManualFillUpFormat.decimal(display, fractionDigits: 0)) \(L10n.volumeUnit(vehicle.units.volume))"
    }
}
