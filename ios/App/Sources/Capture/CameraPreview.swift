import AVFoundation
import SwiftUI
import TankbookCore

/// The live camera preview (design/screens/Capture.dc.html). Wraps
/// `AVCaptureVideoPreviewLayer` in a `UIViewRepresentable`. When no camera
/// device exists (the simulator, UI-test runs) the view keeps its neutral
/// `Theme.Palette.midnight` surface and never crashes - P2.2 wires the real
/// capture session; this task is the surface it lives on.
struct CameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.attachCameraIfAvailable()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

/// The host view: `layerClass` is the preview layer, and the camera session is
/// attached only when a device actually exists.
final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var session: AVCaptureSession?

    func attachCameraIfAvailable() {
        backgroundColor = UIColor(Theme.Palette.midnight)
        guard let device = AVCaptureDevice.default(for: .video),
              let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let newSession = AVCaptureSession()
            guard newSession.canAddInput(input) else { return }
            newSession.addInput(input)
            previewLayer.session = newSession
            previewLayer.videoGravity = .resizeAspectFill
            session = newSession
            newSession.startRunning()
        } catch {
            // No camera available: the neutral midnight surface stays visible.
        }
    }
}
