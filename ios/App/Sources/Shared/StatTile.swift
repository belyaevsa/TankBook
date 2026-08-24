import SwiftUI
import TankbookCore

/// The stat tile BOTH Home's vitals row and Trends' grid render from: an
/// uppercase eyebrow, the figure in DIN with its unit subordinate (hard rule 6),
/// an optional honest caption line, and an optional sparkline. Home and Trends
/// show their numbers through this same component, so they can never disagree
/// about a value or its label.
///
/// A tile is only EVER created with a real value by its caller - the component
/// itself does not know "N/A", "–" or "0.0" (docs/ERRORS.md -> Home/Trends: a
/// vital with nothing to show is omitted, not fabricated).
struct StatTile: View {
    let title: String
    let value: String
    let identifier: String
    /// The unit or symbol ("L/100", "€") rendered small after the figure.
    var unit: String?
    /// The honest label line ("last 3 months", "first estimate · 1 fill cycle").
    var caption: String?
    /// The sparkline series; rendered only when there is enough to draw
    /// honestly (>= 2 points - a single point is noise, not a chart).
    var series: [Double] = []
    /// One accent per series: taillight for fuel figures, headlight for
    /// electric, inkSoft for neutral cost figures (design/screens/TrendsB).
    var seriesColor: Color = Theme.Palette.inkSoft
    /// Bars for the spend tile, a line otherwise (the artboard's charts).
    var bars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.custom(AppFonts.dinAlternateBold, size: 26))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(1)
                }
            }
            if series.count >= 2 {
                Sparkline(values: series, color: seriesColor, bars: bars)
                    .frame(height: 30)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .formCard()
        .accessibilityIdentifier(identifier)
    }
}
