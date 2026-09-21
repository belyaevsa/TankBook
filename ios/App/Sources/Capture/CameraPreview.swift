import AVFoundation
import SwiftUI
import TankbookCore

/// The live camera preview (design/screens/Capture.dc.html). Renders the
/// `CameraController`'s session - the SAME session the shutter captures from,
/// so what the preview shows is what a scan reads. When no camera exists (the
/// simulator, UI-test runs) the view keeps its neutral `Theme.Palette.midnight`
/// surface and never crashes.
///
/// `overlayRects` are the guidance's ready rows (PU.40b), normalised over the
/// analysed frame with a top-left origin. They are drawn as thin outlines in
/// the fuel token (`Theme.Palette.taillight`, hard rule 5).
struct CameraPreview: UIViewRepresentable {
    let controller: CameraController
    var overlayRects: [CGRect] = []
    var frameSize: CGSize = .zero

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.attach(session: controller.captureSession)
        view.setOverlay(overlayRects, frameSize: frameSize)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.attach(session: controller.captureSession)
        uiView.setOverlay(overlayRects, frameSize: frameSize)
    }
}

/// The host view: `layerClass` is the preview layer, and the shared session is
/// attached when a device actually exists. The guidance outlines are sublayers,
/// so they sit above the video and follow the preview's own geometry.
final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var overlayLayers: [CAShapeLayer] = []

    func attach(session: AVCaptureSession?) {
        backgroundColor = UIColor(Theme.Palette.midnight)
        guard let session, let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    /// Draws one thin outline per ready row. The analysed frame is already
    /// rotated upright by the video connection, so its normalised rects map
    /// into the view through the preview's own `.resizeAspectFill` gravity.
    func setOverlay(_ rects: [CGRect], frameSize: CGSize) {
        overlayLayers.forEach { $0.removeFromSuperlayer() }
        overlayLayers = []
        guard !rects.isEmpty, frameSize.width > 0, frameSize.height > 0, bounds.width > 0 else { return }
        let fitted: CGRect = Self.aspectFill(frameSize: frameSize, in: bounds.size)
        let stroke: CGColor = UIColor(Theme.Palette.taillight).cgColor
        var layers: [CAShapeLayer] = []
        for rect in rects {
            let mapped: CGRect = CGRect(x: fitted.minX + rect.minX * fitted.width,
                                        y: fitted.minY + rect.minY * fitted.height,
                                        width: rect.width * fitted.width,
                                        height: rect.height * fitted.height)
            let path: CGPath = UIBezierPath(roundedRect: mapped, cornerRadius: 8).cgPath
            let shape: CAShapeLayer = CAShapeLayer()
            shape.path = path
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = stroke
            shape.lineWidth = 2
            layer.addSublayer(shape)
            layers.append(shape)
        }
        overlayLayers = layers
    }

    /// The rect the frame occupies under `.resizeAspectFill`: scaled to cover
    /// the view and centred, so the overflow is clipped equally on both sides.
    static func aspectFill(frameSize: CGSize, in viewSize: CGSize) -> CGRect {
        let frameWidth: CGFloat = frameSize.width
        let frameHeight: CGFloat = frameSize.height
        let viewWidth: CGFloat = viewSize.width
        let viewHeight: CGFloat = viewSize.height
        guard frameWidth > 0, frameHeight > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let scale: CGFloat = max(viewWidth / frameWidth, viewHeight / frameHeight)
        let scaledWidth: CGFloat = frameWidth * scale
        let scaledHeight: CGFloat = frameHeight * scale
        let x: CGFloat = (viewWidth - scaledWidth) / 2
        let y: CGFloat = (viewHeight - scaledHeight) / 2
        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }
}
