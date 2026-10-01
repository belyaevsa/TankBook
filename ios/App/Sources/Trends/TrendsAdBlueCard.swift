import SwiftUI
import TankbookCore

/// The AdBlue rate under the four Trends tiles, small - never a fifth tile
/// competing with them (docs/DESIGN.md -> AdBlue rows). Shown only once the
/// rate exists, i.e. two top-ups with readings; the caption names the last one.
struct TrendsAdBlueCard: View {
    let stats: AdBlueStats
    let rate: String
    let vehicle: Vehicle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: LogStream.Kind.adBlue.glyph)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LogStream.Kind.adBlue.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("AdBlue")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text(String(format: L10n.localize("last %1$@ %2$@ · %3$@"),
                            AdBlueFormat.volume(stats.lastFill.volumeL, vehicle: vehicle),
                            L10n.volumeUnit(vehicle.units.volume),
                            HomeFormat.day(stats.lastFill.date)))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(rate)
                    .font(.custom(AppFonts.dinAlternateBold, size: 22))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
                Text(AdBlueFormat.rateUnit(vehicle: vehicle))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .lineLimit(1)
        .padding(Theme.Spacing.cardPadding)
        .formCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trendsAdBlueCard")
    }
}
