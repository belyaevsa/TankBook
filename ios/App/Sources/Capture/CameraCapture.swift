import AVFoundation
import UIKit

/// The capture screen's camera session (PJ.1): one `AVCaptureSession` shared by
/// the live preview and the shutter's photo capture, so a frame captured by the
/// shutter is the same frame the preview was showing. `@MainActor @Observable`
/// matches the codebase's other app state (`ServiceInvoiceSession`).
///
/// On the simulator - or any device with no camera - `isReady` stays false, the
/// preview layer stays nil (the `midnight` surface shows instead) and `capture()`
/// returns nil immediately: a missing camera degrades to the manual door, never
/// a crash and never a dead end (hard rules 15, 7).
@MainActor
@Observable
final class CameraController: NSObject {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var didConfigure = false
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    /// True once a camera is attached and running (false on the simulator).
    private(set) var isReady = false

    /// The running session, exposed so the preview layer can render it.
    var captureSession: AVCaptureSession? {
        isReady ? session : nil
    }

    /// Configures the session once: video input + photo output, and starts
    /// running. Idempotent; a device without a camera leaves `isReady` false.
    func start() {
        guard !didConfigure else { return }
        didConfigure = true
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else { return }
            session.addInput(input)
            session.addOutput(photoOutput)
            session.startRunning()
            isReady = true
        } catch {
            // No camera available: capture() returns nil, the manual door stands.
        }
    }

    /// Captures one photo frame. Returns nil when no camera is available or the
    /// capture fails - the caller then degrades to the ordinary manual form.
    func capture() async -> UIImage? {
        guard isReady, captureContinuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func deliver(_ image: UIImage?) {
        captureContinuation?.resume(returning: image)
        captureContinuation = nil
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    /// Runs on the photo queue; hops to the main actor to resume the capture
    /// continuation (the same nonisolated -> MainActor hand-off pattern as
    /// `DocumentCamera.Coordinator`).
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = error == nil ? photo.cgImageRepresentation().map { UIImage(cgImage: $0) } : nil
        Task { @MainActor [weak self] in
            self?.deliver(image)
        }
    }
}
