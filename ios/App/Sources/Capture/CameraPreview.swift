import AVFoundation
import SwiftUI
import TankbookCore

/// The live camera preview (design/screens/Capture.dc.html). Renders the
/// `CameraController`'s session - the SAME session the shutter captures from,
/// so what the preview shows is what a scan reads. When no camera exists (the
/// simulator, UI-test runs) the view keeps its neutral `Theme.Palette.midnight`
/// surface and never crashes.
struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.attach(session: controller.captureSession)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.attach(session: controller.captureSession)
    }
}

/// The host view: `layerClass` is the preview layer, and the shared session is
/// attached when a device actually exists.
final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    func attach(session: AVCaptureSession?) {
        backgroundColor = UIColor(Theme.Palette.midnight)
        guard let session, let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }
}
