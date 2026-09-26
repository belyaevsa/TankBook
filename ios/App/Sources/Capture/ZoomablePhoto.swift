import SwiftUI
import TankbookCore
import UIKit

/// A photo the user can zoom and turn to compare it with the numbers beside it:
/// pinch or the − / + buttons to zoom, drag to move a zoomed photo, a double tap
/// to go between fitted and 2×, and a turn button for a photo taken sideways.
/// Fitted, never cropped, at 1× (the corner a total is printed in must stay in
/// view).
struct ZoomablePhoto: View {
    let image: UIImage
    /// Clockwise degrees, a multiple of 90.
    let rotationDegrees: Double
    let onTurn: () -> Void

    static let maximumZoom: CGFloat = 5
    static let zoomStep: CGFloat = 1.5

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: Self.turned(image, degrees: rotationDegrees))
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(zoom)
                .offset(offset)
                .gesture(magnify.simultaneously(with: drag))
                .onTapGesture(count: 2) { setZoom(zoom > 1 ? 1 : 2) }
                .clipped()
                .accessibilityLabel(Text("The photo to check"))
                .accessibilityIdentifier("captureVerifyImage")
        }
        .overlay(alignment: .bottomTrailing) { controls }
        .onChange(of: rotationDegrees) { setZoom(1) }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(settledZoom * value.magnification, 1), Self.maximumZoom) }
            .onEnded { _ in
                settledZoom = zoom
                if zoom == 1 { resetOffset() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(width: settledOffset.width + value.translation.width,
                                height: settledOffset.height + value.translation.height)
            }
            .onEnded { _ in settledOffset = offset }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("minus.magnifyingglass", label: "Zoom out", identifier: "captureVerifyZoomOut") {
                setZoom(zoom / Self.zoomStep)
            }
            control("plus.magnifyingglass", label: "Zoom in", identifier: "captureVerifyZoomIn") {
                setZoom(zoom * Self.zoomStep)
            }
            control("rotate.right", label: "Turn the photo", identifier: "captureVerifyTurn", action: onTurn)
        }
        .padding(10)
    }

    private func control(_ symbol: String, label: LocalizedStringKey, identifier: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.dash.opacity(0.85))
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = min(max(value, 1), Self.maximumZoom)
            settledZoom = zoom
            if zoom == 1 { resetOffset() }
        }
    }

    private func resetOffset() {
        offset = .zero
        settledOffset = .zero
    }

    /// The photo redrawn upright, then turned clockwise by whole quarter
    /// turns - a turned image lays out at its own aspect, where a rotation
    /// effect would keep the original frame.
    static func turned(_ image: UIImage, degrees: Double) -> UIImage {
        let turns = ((Int(degrees) / 90) % 4 + 4) % 4
        guard turns != 0 else { return image }
        let upright = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        guard let cgImage = upright.cgImage else { return image }
        let orientation: UIImage.Orientation = [.up, .right, .down, .left][turns]
        return UIImage(cgImage: cgImage, scale: upright.scale, orientation: orientation)
    }
}
