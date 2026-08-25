import SwiftUI
import TankbookCore

// MARK: - Detection frame

/// The taillight corner brackets + receipt card over the detected surface
/// (design/screens/Capture.dc.html). Presentation only in P2.1: the lines come
/// from an injected `CaptureDetection` and are rendered verbatim (they are
/// simulated OCR data, not copy, so they never go through the String Catalog).
struct DetectionFrame: View {
    let lines: [String]

    var body: some View {
        ZStack {
            DetectionCorners()
                .stroke(Theme.Palette.taillight,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            receiptCard
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .rotationEffect(.degrees(-2))
        }
        .frame(width: 250, height: 330)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("captureDetectionFrame")
    }

    private var receiptCard: some View {
        VStack(spacing: 8) {
            Text(lines.first ?? "")
                .font(.system(size: 10, design: .monospaced))
                .multilineTextAlignment(.center)
            Rectangle()
                .stroke(Theme.Palette.inkSoft.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
            ForEach(lines.dropFirst(), id: \.self) { line in
                Text(line)
                    .font(.system(size: 8, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.Palette.ink)
        .padding(12)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: Theme.Palette.midnight.opacity(0.55), radius: 12, y: 4)
    }
}

/// The four corner brackets (artboard: 34pt arms, 8pt corner radius).
private struct DetectionCorners: Shape {
    private let arm: CGFloat = 30
    private let radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: arm, y: 0))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: arm))

        path.move(to: CGPoint(x: width - arm, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: radius), control: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: arm))

        path.move(to: CGPoint(x: 0, y: height - arm))
        path.addLine(to: CGPoint(x: 0, y: height - radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: height), control: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: arm, y: height))

        path.move(to: CGPoint(x: width - arm, y: height))
        path.addLine(to: CGPoint(x: width - radius, y: height))
        path.addQuadCurve(to: CGPoint(x: width, y: height - radius),
                          control: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width, y: height - arm))
        return path
    }
}
