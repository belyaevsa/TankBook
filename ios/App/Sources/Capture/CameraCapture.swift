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
    /// PU.40b: the preview guidance's frame source. The same session as the
    /// shutter, so what the detector sees is what the shutter will capture.
    private let videoOutput = AVCaptureVideoDataOutput()
    private var didConfigure = false
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?
    /// The video device `start()` attached, retained so the DEBUG Capture Lab
    /// can configure it per preset. Nil on the simulator.
    private var device: AVCaptureDevice?
    #if DEBUG
    /// Retains the lab capture's delegate until its continuation resumes.
    private var labDelegate: LabCaptureDelegate?
    #endif

    /// True once a camera is attached and running (false on the simulator).
    private(set) var isReady = false

    /// The live preview's guidance (PU.40b), published for `CaptureView`'s
    /// caption and overlay. Nothing runs until `setGuidanceActive(true)`.
    let guidance = PreviewGuidance()

    /// Runs the detector on the video frames and forwards the rows to
    /// `guidance` on the main actor. `lazy` so its `@Sendable` handler can
    /// capture the already-initialised `guidance`; ignored by `@Observable`,
    /// which cannot track a lazily-initialised property.
    @ObservationIgnored private lazy var frameAnalyzer = PreviewFrameAnalyzer { [guidance] rows, size, ms in
        Task { @MainActor in
            guidance.observe(rows: rows, frameSize: size, analysisMs: ms)
        }
    }

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
        self.device = device
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else { return }
            session.addInput(input)
            session.addOutput(photoOutput)
            // PU.40b: a second output on the SAME session delivers frames to
            // the detector. Late frames are dropped so a slow analysis never
            // queues up; the delegate queue serialises what remains.
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                frameAnalyzer.attach(to: videoOutput)
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

    // MARK: - Preview guidance (PU.40b)

    /// Starts or stops the preview detector. `active` with no reader (the
    /// bundle's models missing) leaves the analyser idle, so guidance never
    /// runs without the reader behind it. Turning it off clears the published
    /// state and undoes a zoom the guidance offered.
    func setGuidanceActive(_ active: Bool) {
        frameAnalyzer.set(reader: active ? CapturePipeline.pumpReader : nil, active: active)
        guard active else {
            guidance.reset()
            resetZoom()
            return
        }
        #if DEBUG
        // The simulator's `-captureCameraTestFrame` double has no camera to
        // deliver a stream; feed the same frame enough times for the debouncer
        // to publish. The feeds are spaced wider than the analyser's own
        // throttle, or the analyser would drop the second and third frames and
        // the state would never leave `searching`.
        if let frame = testFrame, let cgImage = frame.cgImage {
            Task {
                for _ in 0..<GuidanceDebouncer.requiredFrames {
                    frameAnalyzer.feed(cgImage)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        #endif
    }

    /// Whether the active device can zoom far enough to offer the hint's 2×
    /// tap. False on the simulator (no device).
    var hasZoomRange: Bool {
        guard let device else { return false }
        return device.activeFormat.videoMaxZoomFactor >= 2
    }

    /// Applies a zoom factor, clamped to the device's range. The guidance's 2×
    /// offer calls this; `resetZoom` undoes it when the screen is left.
    func applyZoom(_ factor: CGFloat) {
        guard let device, device.activeFormat.videoMaxZoomFactor >= factor else { return }
        try? device.lockForConfiguration()
        device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor),
                                     device.maxAvailableVideoZoomFactor)
        device.unlockForConfiguration()
    }

    func resetZoom() {
        applyZoom(1)
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
/// PU.39 - the Capture Lab's camera door. Everything here is DEBUG-only: the
/// lab never ships, and the Release gate is the proof. The ordinary `capture()`
/// above is untouched.
extension CameraController {

    /// One captured frame exactly as the camera delivered it: the JPEG bytes
    /// (untouched, so the corpus intake can take them), the decoded image, the
    /// capture metadata and the delivered pixel size.
    struct CaptureLabFrame: @unchecked Sendable {
        let data: Data
        let image: UIImage
        let metadata: [String: Any]
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// The live device's capabilities, read from AVFoundation. No device (the
    /// simulator) reports none, so every preset records what it could not do.
    var labCapabilities: CaptureLabCapabilities {
        guard let device else { return .none }
        var capabilities = CaptureLabCapabilities()
        capabilities.focusPointOfInterest = device.isFocusPointOfInterestSupported
        capabilities.exposurePointOfInterest = device.isExposurePointOfInterestSupported
        capabilities.continuousAutoFocus = device.isFocusModeSupported(.continuousAutoFocus)
        capabilities.continuousAutoExposure = device.isExposureModeSupported(.continuousAutoExposure)
        capabilities.lockedFocus = device.isFocusModeSupported(.locked)
        capabilities.lockedExposure = device.isExposureModeSupported(.locked)
        // No `isExposureTargetBiasSupported` exists; a device whose bias range
        // is a single point cannot take a bias, and the setter would throw.
        capabilities.exposureBias = device.maxExposureTargetBias > device.minExposureTargetBias
        capabilities.zoom = device.activeFormat.videoMaxZoomFactor > 1
        if device.isVirtualDevice {
            // A switch-over factor in the telephoto range is the honest 2×
            // point on a wide+telephoto pair.
            for number in device.virtualDeviceSwitchOverVideoZoomFactors where number.doubleValue >= 1.9 {
                capabilities.telephotoSwitchOverZoom = CGFloat(number.doubleValue)
                break
            }
        }
        capabilities.flash = device.hasFlash
        capabilities.highSessionPreset = session.canSetSessionPreset(.high)
        return capabilities
    }

    /// Applies `plan` to the live session, device and output. Every preset
    /// starts from the control: focus and exposure continuous, bias 0, zoom 1,
    /// the `.photo` session - so one preset never rides the previous one's
    /// settings. `locked` waits for convergence before it locks.
    func applyLabPlan(_ plan: CaptureLabPlan) async {
        applySessionPreset(plan)
        photoOutput.maxPhotoQualityPrioritization = plan.qualityPrioritization ?? .balanced
        guard let device else { return }
        resetToControl(device)
        applyFocusAndExposure(plan, to: device)
        // The convergence wait happens OUTSIDE the configuration lock:
        // `isAdjustingFocus` and `isAdjustingExposure` are read-only
        // observations, and holding the lock while the lens hunts blocks the
        // session.
        if plan.waitForConvergence { await waitForConvergence(device) }
        guard plan.focusMode == .locked || plan.exposureMode == .locked else { return }
        try? device.lockForConfiguration()
        if let mode = plan.focusMode, device.isFocusModeSupported(mode) { device.focusMode = mode }
        if let mode = plan.exposureMode, device.isExposureModeSupported(mode) { device.exposureMode = mode }
        device.unlockForConfiguration()
    }

    private func applySessionPreset(_ plan: CaptureLabPlan) {
        if plan.sessionPresetHigh {
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        } else if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
    }

    /// The control baseline every preset starts from: continuous focus and
    /// exposure, no bias, no zoom.
    private func resetToControl(_ device: AVCaptureDevice) {
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.maxExposureTargetBias > device.minExposureTargetBias {
            device.setExposureTargetBias(0, completionHandler: nil)
        }
        if device.activeFormat.videoMaxZoomFactor > 1 { device.videoZoomFactor = 1 }
        device.unlockForConfiguration()
    }

    /// Applies the plan's points, bias and zoom, each behind its capability.
    private func applyFocusAndExposure(_ plan: CaptureLabPlan, to device: AVCaptureDevice) {
        try? device.lockForConfiguration()
        if let point = plan.focusPoint, device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
        }
        if let point = plan.exposurePoint, device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
        }
        if let bias = plan.exposureBias, device.maxExposureTargetBias > device.minExposureTargetBias {
            device.setExposureTargetBias(min(max(bias, device.minExposureTargetBias),
                                            device.maxExposureTargetBias),
                                         completionHandler: nil)
        }
        if let zoom = plan.zoomFactor, device.activeFormat.videoMaxZoomFactor >= zoom {
            device.videoZoomFactor = min(max(zoom, device.minAvailableVideoZoomFactor),
                                         device.maxAvailableVideoZoomFactor)
        }
        device.unlockForConfiguration()
    }

    /// Polls until focus and exposure stop adjusting, capped at 1.5 s so a lens
    /// that never settles cannot stall the run.
    private func waitForConvergence(_ device: AVCaptureDevice) async {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, device.isAdjustingFocus || device.isAdjustingExposure {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Captures one frame under `plan`. On the simulator's `-captureCameraTestFrame`
    /// double it hands back the fixture as JPEG bytes, so a UI test can drive a
    /// whole run without a camera.
    func captureLabFrame(_ plan: CaptureLabPlan) async -> CaptureLabFrame? {
        guard isReady else { return nil }
        if let testFrame {
            let pixels = CGSize(width: testFrame.size.width * testFrame.scale,
                                height: testFrame.size.height * testFrame.scale)
            let data = testFrame.jpegData(compressionQuality: 1) ?? Data()
            return CaptureLabFrame(data: data, image: testFrame, metadata: [:],
                                   pixelWidth: Int(pixels.width), pixelHeight: Int(pixels.height))
        }
        guard captureContinuation == nil, labDelegate == nil else { return nil }
        let settings = AVCapturePhotoSettings()
        if let quality = plan.qualityPrioritization {
            settings.photoQualityPrioritization = quality
        }
        if plan.flashOff, photoOutput.supportedFlashModes.contains(.off) {
            settings.flashMode = .off
        }
        applyRotation()
        let frame = await withCheckedContinuation { continuation in
            let delegate = LabCaptureDelegate(continuation: continuation)
            labDelegate = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        labDelegate = nil
        return frame
    }
}

/// The lab capture's delegate: builds the delivered bytes, image, metadata and
/// pixel size and resumes the continuation once. Separate from
/// `CameraController`'s own delegate so the ordinary `capture()` path is
/// byte-for-byte unchanged.
private final class LabCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<CameraController.CaptureLabFrame?, Never>
    private let lock = NSLock()
    private var finished = false

    init(continuation: CheckedContinuation<CameraController.CaptureLabFrame?, Never>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let image = data.flatMap { UIImage(data: $0) }
            ?? photo.cgImageRepresentation().map { UIImage(cgImage: $0) }
        let dimensions = photo.resolvedSettings.photoDimensions
        let frame: CameraController.CaptureLabFrame?
        if let data, let image {
            frame = CameraController.CaptureLabFrame(data: data, image: image, metadata: photo.metadata,
                                                     pixelWidth: Int(dimensions.width),
                                                     pixelHeight: Int(dimensions.height))
        } else {
            frame = nil
        }
        finish(frame)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        // A capture that never delivered a photo (an error before processing)
        // must still resume, or the run would hang.
        if error != nil { finish(nil) }
    }

    private func finish(_ frame: CameraController.CaptureLabFrame?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(returning: frame)
    }
}

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
