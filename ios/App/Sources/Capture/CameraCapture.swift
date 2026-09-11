import AVFoundation
import Foundation
import UIKit

/// The capture screen's camera session (PJ.1): one `AVCaptureSession` shared by
/// the live preview and the shutter's photo capture, so a frame captured by the
/// shutter is the same frame the preview was showing. `@MainActor @Observable`
/// matches the codebase's other app state (`ServiceInvoiceSession`).
///
/// On the simulator - or any device with no camera - `isReady` stays false, the
/// preview layer stays nil (the `midnight` surface shows instead) and `capture()`
/// returns nil immediately. The caller decides what a nil means; `CaptureView`
/// surfaces the camera-fault next step rather than a silent no-op (hard rules
/// 15, 7).
@MainActor
@Observable
final class CameraController: NSObject {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var didConfigure = false
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    /// True once a camera is attached and running (false on the simulator).
    private(set) var isReady = false

    #if DEBUG
    /// The `-captureCameraTestFrame <path>` test double: a simulated camera.
    /// The simulator has no camera, so without it `start()` leaves `isReady`
    /// false and a UI test could not tell a started session from an unstarted
    /// one. `-captureFixtureImage` cannot stand in here because it bypasses
    /// `capture()` entirely. Production never passes the argument.
    private var testFrame: UIImage? {
        guard let path = ProcessInfo.processInfo.arguments.captureCameraTestFramePath else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
    #endif

    /// The running session, exposed so the preview layer can render it.
    var captureSession: AVCaptureSession? {
        isReady ? session : nil
    }

    /// Configures the session once: video input + photo output, and starts
    /// running. Idempotent, so the first permission resolve and the return from
    /// Settings can both call it; a device without a camera leaves `isReady`
    /// false. Under the DEBUG `-captureCameraTestFrame` double it reports ready
    /// without touching the hardware, so a UI test can prove the session was
    /// started.
    func start() {
        guard !didConfigure else { return }
        didConfigure = true
        #if DEBUG
        if testFrame != nil {
            isReady = true
            return
        }
        #endif
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else { return }
            session.addInput(input)
            session.addOutput(photoOutput)
            // `.photo` delivers the sensor's full photo resolution, not the
            // default `.high` (~1080p) - the app OCRs small print, and every
            // pixel the sensor can spare is a pixel the recognizer can read.
            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
            }
            // Receipts and pump displays are shot from up close; restrict the
            // focus range to `.near` when the hardware supports it so the digits
            // the pipeline must read are in focus, not the forecourt behind.
            try device.lockForConfiguration()
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
            session.startRunning()
            isReady = true
        } catch {
            // No camera available: capture() returns nil, the manual door stands.
        }
    }

    /// Captures one photo frame. Returns nil when no camera is available or the
    /// capture fails; a nil from this real-camera path is the caller's cue to
    /// surface the camera-fault next step (`CaptureView.captureFrame`).
    func capture() async -> UIImage? {
        guard isReady, captureContinuation == nil else { return nil }
        #if DEBUG
        if let testFrame { return testFrame }
        #endif
        // RV.49: the sensor delivers landscape pixels; the connection's rotation
        // must be told the interface orientation or the photo (and its EXIF)
        // arrive sideways and Vision reads them wrong. The app is portrait-only
        // (Info.plist), so this is `.portrait` today; the mapping is general.
        applyRotation()
        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    /// Sets the photo connection's `videoRotationAngle` from the current
    /// interface orientation. Standard mapping: portrait 90, upside-down 270,
    /// landscape-left 180, landscape-right 0.
    private func applyRotation() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .interfaceOrientation ?? .portrait
        switch orientation {
        case .portrait: connection.videoRotationAngle = 90
        case .portraitUpsideDown: connection.videoRotationAngle = 270
        case .landscapeLeft: connection.videoRotationAngle = 180
        case .landscapeRight: connection.videoRotationAngle = 0
        default: connection.videoRotationAngle = 90
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
        guard error == nil else {
            Task { @MainActor [weak self] in self?.deliver(nil) }
            return
        }
        // `fileDataRepresentation()` (not `cgImageRepresentation()`) so the
        // orientation the connection recorded survives into the `UIImage`: a
        // `UIImage(data:)` carries the EXIF orientation, where the old
        // `UIImage(cgImage:)` discarded it (RV.49).
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = photo.cgImageRepresentation().map { UIImage(cgImage: $0) }
        }
        Task { @MainActor [weak self] in
            self?.deliver(image)
        }
    }
}

#if DEBUG
extension Array where Element == String {
    /// The `-captureCameraTestFrame <path>` override, if present. It makes
    /// `CameraController.start()` succeed with a simulated camera and
    /// `capture()` hand back the file, so a UI test can prove the session was
    /// started (the `-captureFixtureImage` double bypasses `capture()` and so
    /// cannot). Production never passes the argument.
    var captureCameraTestFramePath: String? {
        guard let index = firstIndex(of: "-captureCameraTestFrame"), index + 1 < count else {
            return nil
        }
        return self[index + 1]
    }
}
#endif
