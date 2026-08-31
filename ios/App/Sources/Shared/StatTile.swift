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
    /// The series' direction for VoiceOver ("improving" / "worsening"), when
    /// the metric is lower-is-better and the series supports one. `nil` (the
    /// common case) is silently omitted from the label - never "steady".
    var trend: TrendDirection?

    /// The figure's VoiceOver label: value + unit + trend, in that order
    /// (docs/DESIGN.md -> Accessibility floor: a bare number read aloud is
    /// useless). The subordinate `unit` is hidden from VoiceOver on its own -
    /// reading "6.8" then "L/100" as two announcements is the failure the
    /// combined figure exists to prevent - and the trend, when the series
    /// supports one, is appended. The eyebrow (title) and caption remain their
    /// own elements, so a tile reads "CONSUMPTION", "6.8 L/100, improving",
    /// "last 5 months".
    private var figureVoiceOverLabel: String {
        let figure = unit.map { "\(value) \($0)" } ?? value
        if let trend { return "\(figure), \(L10n.trend(trend))" }
        return figure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkSoft)
                // Two lines, never one (P6.13): RU's "РАСХОДЫ ЗА АВГУСТ" runs
                // 20-30% longer than EN's "AUGUST SPEND" and clips at the
                // large Dynamic Type of P5.3's "-xl" captures under a single
                // line. Letting the label wrap - the same escape the parts rows
                // use - beats clipping, and the tile grows to match (Trends'
                // grid row is as tall as its tallest cell, so a wrapped title
                // never collides).
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.custom(AppFonts.dinAlternateBold, size: 26))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(figureVoiceOverLabel)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(1)
                        .accessibilityHidden(true)
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
        // Fill the grid cell in BOTH axes: a `LazyVGrid` row is as tall as its
        // tallest cell, but a cell that does not stretch leaves the shorter
        // tile floating in a short card, so a row of four tiles rendered as
        // four different card heights. Height parity is what makes it read as
        // a grid rather than a collage (docs/DESIGN.md - Trends tile grid).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .formCard()
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - The subtitle's wrapping flow (P6.13)

/// A wrapping flow for the log entry subtitle (`HomeSections.subtitleLine`).
/// `HStack` cannot wrap, so at Dynamic Type XL the segments overflowed the row
/// and `.lineLimit(1)` clipped the odometer and the date in both languages
/// (`123 6… · Aug…`). This flows the segment units onto a second line the way
/// the parts rows wrap; each unit carries its own trailing "·", so a separator
/// stays glued to its segment and never starts a line (the typographic rule
/// that a punctuation mark never begins one).
struct SubtitleFlow: Layout {
    /// Horizontal gap between units on a line.
    var spacing: CGFloat
    /// Vertical gap between wrapped lines.
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let height = placements(for: sizes, leading: 0, maxWidth: maxWidth)
            .map { $0.origin.y + $0.size.height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let placements = placements(for: sizes, leading: bounds.minX,
                                    maxWidth: bounds.maxX)
        for (index, subview) in subviews.enumerated() {
            let placement = placements[index]
            // `placements` computes y from 0 (it knows only the line stack) while
            // x is already absolute, so y MUST be offset into `bounds`. Without
            // this the segments are placed at absolute y ~ 0 - the row reserves
            // its height and paints nothing where the subtitle belongs, which a
            // frame assertion cannot see because the frames still exist.
            subview.place(at: CGPoint(x: placement.origin.x,
                                      y: bounds.minY + placement.origin.y),
                          proposal: ProposedViewSize(placement.size))
        }
    }

    /// The one layout decision, shared by the size and placement passes so they
    /// can never disagree: a unit that does not fit the current line wraps to
    /// the next one, whole.
    private func placements(for sizes: [CGSize], leading: CGFloat,
                            maxWidth: CGFloat) -> [(origin: CGPoint, size: CGSize)] {
        var result: [(origin: CGPoint, size: CGSize)] = []
        var x = leading
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in sizes {
            if x > leading, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = leading
                lineHeight = 0
            }
            result.append((origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return result
    }
}
