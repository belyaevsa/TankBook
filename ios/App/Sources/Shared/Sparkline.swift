import SwiftUI
import TankbookCore

/// A minimal sparkline: thin `inkSoft` grid lines, one accent series, no chart
/// junk (docs/DESIGN.md: "no chart junk, thin inkSoft grid, taillight/headlight
/// series only"). Bars for the spend tile, a line otherwise.
///
/// A series slot may be `nil` - a month inside the plotted window whose figure
/// is not storable (rate-pending, RV.112). A nil slot is a real hole, never a
/// value: the line chart BREAKS its path there (it must not bridge the gap with
/// a straight line, which would read as "spend fell"), and the bar chart draws
/// nothing in that slot while keeping the slot's position so later bars do not
/// shift.
struct Sparkline: View {
    let values: [Double?]
    let color: Color
    var bars = false

    var body: some View {
        GeometryReader { geo in
            if bars {
                barChart(in: geo.size)
            } else {
                lineChart(in: geo.size)
            }
        }
    }

    // MARK: Line

    private func lineChart(in size: CGSize) -> some View {
        let coords = Self.normalized(values, in: size)
        return ZStack(alignment: .topLeading) {
            grid(size)
            Path { path in
                var hasOpenSegment = false
                for point in coords {
                    guard let point else {
                        // A gap ends the current segment: the next real point
                        // starts a NEW segment (move), never a line across the
                        // hole (RV.112).
                        hasOpenSegment = false
                        continue
                    }
                    if hasOpenSegment {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                        hasOpenSegment = true
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = coords.compactMap({ $0 }).last {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .position(last)
            }
        }
    }

    /// Normalised to the drawing area with a small vertical inset, preserving
    /// the true shape of the series (a flat series stays a flat centre line -
    /// no invented variation, no fake baseline). Gap slots stay `nil` but keep
    /// their index position, so nothing draws across a hole.
    private static func normalized(_ values: [Double?], in size: CGSize) -> [CGPoint?] {
        let topPad: CGFloat = 4
        let bottomPad: CGFloat = 4
        let present = values.compactMap { $0 }
        let usableHeight = size.height - topPad - bottomPad
        let span = (present.max() ?? 0) - (present.min() ?? 0)
        guard span > 0 else {
            let y = size.height / 2
            return values.indices.map { index in
                values[index].map { _ in
                    CGPoint(x: xPosition(index, count: values.count, width: size.width), y: y)
                }
            }
        }
        let minValue = present.min() ?? 0
        return values.enumerated().map { index, value in
            guard let value else { return nil }
            let ratio = (value - minValue) / span
            let y = topPad + (1 - ratio) * usableHeight
            return CGPoint(x: xPosition(index, count: values.count, width: size.width), y: y)
        }
    }

    private static func xPosition(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        count <= 1 ? width / 2 : width * CGFloat(index) / CGFloat(count - 1)
    }

    // MARK: Bars

    private func barChart(in size: CGSize) -> some View {
        let present = values.compactMap { $0 }
        let maxValue = present.max() ?? 1
        let slot = size.width / CGFloat(max(values.count, 1))
        let barWidth = max(4, slot * 0.55)
        let bottomInset: CGFloat = 3
        let usableHeight = size.height - bottomInset
        return ZStack(alignment: .topLeading) {
            grid(size)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                // A gap slot keeps its position but draws no bar - the hole is
                // the honest rendering of a month whose total is not storable.
                if let value {
                    let height = max(2, CGFloat(value) / CGFloat(maxValue) * usableHeight)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: barWidth, height: height)
                        .position(x: CGFloat(index) * slot + slot / 2,
                                  y: size.height - bottomInset - height / 2)
                }
            }
        }
    }

    // MARK: Grid

    /// Thin `inkSoft` rules at the thirds plus a baseline - the artboard's
    /// quiet grid, never a chart-junk axis.
    private func grid(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height * CGFloat(index + 1) / 3))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(index + 1) / 3))
                }
                .stroke(Theme.Palette.inkSoft.opacity(0.22), lineWidth: 1)
            }
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height - 0.5))
                path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            }
            .stroke(Theme.Palette.inkSoft.opacity(0.35), lineWidth: 1)
        }
    }
}
