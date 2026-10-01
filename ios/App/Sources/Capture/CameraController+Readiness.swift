import AVFoundation
import Foundation
import TankbookCore

/// PJ.16 - the torch and the readiness hints, beside the session they act on.
extension CameraController {
    /// UserDefaults key of the remembered torch state (device-local, never synced -
    /// docs/SCHEMA.md, capture conveniences).
    static let torchKey = "capture.torchOn"

    /// Whether the active camera has a torch. The simulator has none; the DEBUG
    /// `-captureFakeTorch` stands one in so the toggle can be tested.
    var hasTorch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-captureFakeTorch") { return true }
        #endif
        return device?.hasTorch ?? false
    }

    /// The torch's remembered state.
    var torchOn: Bool {
        UserDefaults.standard.bool(forKey: Self.torchKey)
    }

    /// Turns the torch on or off and remembers the choice for the next capture.
    func setTorch(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.torchKey)
        torchRevision += 1
        applyTorch(on)
        AppLog.shared.emit(CaptureReadiness(action: on ? "torch.on" : "torch.off"))
    }

    /// Re-applies the remembered state once the session runs.
    func restoreTorch() {
        applyTorch(torchOn)
    }

    /// The screen went away: the light goes off, the preference stays.
    func suspendTorch() {
        applyTorch(false)
    }

    private func applyTorch(_ on: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    /// Whether the hints may run: on a real camera, or in DEBUG when a test
    /// asks (`-captureHintsEnabled`) - the simulator has no frames, and without
    /// the gate every capture screen in a UI test would show "fill the frame"
    /// after a few seconds.
    var hintsAllowed: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-captureHintsEnabled") { return true }
        #endif
        return device != nil
    }

    /// Starts or stops the readiness hints for the capture screen.
    func setHintsActive(_ active: Bool) {
        guard active, hintsAllowed else {
            frameAnalyzer.setHintSampler(nil)
            hints.stop()
            return
        }
        let hints = hints
        frameAnalyzer.setHintSampler(CaptureHintSampler { luma, document in
            Task { @MainActor in hints.observe(luma: luma, document: document) }
        })
        let guidance = guidance
        hints.start(displayInView: { guidance.state != .searching })
    }
}

/// PJ.16: the session's one-time configuration, run on the session queue. The
/// capture objects are not `Sendable`; this box carries them across, and only
/// the session queue touches them until `isReady` publishes on the main actor.
struct CaptureSessionSetup: @unchecked Sendable {
    let session: AVCaptureSession
    let photoOutput: AVCapturePhotoOutput
    let videoOutput: AVCaptureVideoDataOutput
    let device: AVCaptureDevice
    let analyzer: PreviewFrameAnalyzer

    func configureAndRun() -> Bool {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else { return false }
            session.addInput(input)
            session.addOutput(photoOutput)
            // PU.40b: a second output on the SAME session delivers frames to
            // the detector. Late frames are dropped so a slow analysis never
            // queues up; the delegate queue serialises what remains.
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                analyzer.attach(to: videoOutput)
                // The sensor delivers landscape pixels; rotate them upright so
                // the detector (trained on upright displays) sees what the user
                // sees, and the normalised rows match the preview's space.
                if let connection = videoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
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
            return true
        } catch {
            // No camera available: capture() returns nil, the manual door stands.
            return false
        }
    }
}
