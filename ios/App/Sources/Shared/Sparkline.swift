import SwiftUI
import TankbookCore

/// A minimal sparkline: thin `inkSoft` grid lines, one accent series, no chart
/// junk (docs/DESIGN.md: "no chart junk, thin inkSoft grid, taillight/headlight
/// series only"). Bars for the spend tile, a line otherwise.
struct Sparkline: View {
    let values: [Double]
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
        let points = Self.normalized(values, in: size)
        return ZStack(alignment: .topLeading) {
            grid(size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .position(last)
            }
        }
    }

    /// Normalised to the drawing area with a small vertical inset, preserving
    /// the true shape of the series (a flat series stays a flat centre line -
    /// no invented variation, no fake baseline).
    private static func normalized(_ values: [Double], in size: CGSize) -> [CGPoint] {
        let topPad: CGFloat = 4
        let bottomPad: CGFloat = 4
        let span = (values.max() ?? 0) - (values.min() ?? 0)
        guard span > 0 else {
            let y = size.height / 2
            return values.indices.map { index in
                CGPoint(x: xPosition(index, count: values.count, width: size.width), y: y)
            }
        }
        let minValue = values.min() ?? 0
        let usableHeight = size.height - topPad - bottomPad
        return values.enumerated().map { index, value in
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
        let maxValue = values.max() ?? 1
        let slot = size.width / CGFloat(values.count)
        let barWidth = max(4, slot * 0.55)
        let bottomInset: CGFloat = 3
        let usableHeight = size.height - bottomInset
        return ZStack(alignment: .topLeading) {
            grid(size)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let height = max(2, CGFloat(value) / CGFloat(maxValue) * usableHeight)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: barWidth, height: height)
                    .position(x: CGFloat(index) * slot + slot / 2,
                              y: size.height - bottomInset - height / 2)
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
