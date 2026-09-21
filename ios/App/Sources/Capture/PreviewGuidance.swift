import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Observation
import TankbookCore

/// What the live preview can tell the user before the shutter (PU.40b):
/// whether the reader will have a display to read. The states are the reader's
/// own funnel - no row, rows too small, one stacked row short, ready - and the
/// rules are `PumpDisplayCapture`'s, never a second copy.
enum CaptureGuidanceState: String, Equatable, Sendable {
    /// No detected row: no overlay, the screen's own caption stands.
    case searching
    /// Rows found but none passes the size rule: move closer (a zoom offer when
    /// the device has one).
    case tooSmall
    /// At least one row passes the size rule but two do not stack: the display
    /// is partly out of frame or at an angle.
    case oneRow
    /// Two stacked rows pass the size rules: the reader will have a display.
    case ready

    /// The classification of one frame's rescued detector rows. `textLines` is
    /// deliberately zero: the preview has no Vision text-line count, and a
    /// receipt's printed digits are under the size rule anyway, so the size
    /// test alone keeps a receipt in `searching` or `tooSmall`.
    static func classify(rows: [PumpRowDetector.Row]) -> CaptureGuidanceState {
        guard !rows.isEmpty else { return .searching }
        if PumpDisplayCapture.fastVerdict(rows: rows, textLines: 0) { return .ready }
        return rows.contains(where: { PumpDisplayCapture.passesSize($0) }) ? .oneRow : .tooSmall
    }
}

/// Holds a new state for `requiredFrames` consecutive frames before publishing
/// it, so one noisy frame does not flicker the hint. The very first observation
/// of a state counts as one frame; a return to the published state resets the
/// run.
struct GuidanceDebouncer {
    static let requiredFrames = 3

    private(set) var published: CaptureGuidanceState = .searching
    private var candidate: CaptureGuidanceState = .searching
    private var candidateFrames = 0

    mutating func observe(_ next: CaptureGuidanceState) -> CaptureGuidanceState {
        guard next != published else {
            candidate = next
            candidateFrames = 0
            return published
        }
        if next == candidate {
            candidateFrames += 1
        } else {
            candidate = next
            candidateFrames = 1
        }
        if candidateFrames >= Self.requiredFrames {
            published = next
            candidateFrames = 0
        }
        return published
    }

    mutating func reset() {
        published = .searching
        candidate = .searching
        candidateFrames = 0
    }
}

/// The published preview guidance. Written only on the main actor - the
/// analyser hands its rows over - and read by `CaptureView`'s caption and
/// overlay. `overlayRects` and `frameSize` are normalised over the analysed
/// frame, top-left origin, which is how the preview maps them.
@MainActor
@Observable
final class PreviewGuidance {
    private(set) var state: CaptureGuidanceState = .searching
    private(set) var overlayRects: [CGRect] = []
    private(set) var framesAnalysed = 0
    private(set) var lastAnalysisMs = 0
    private(set) var frameSize: CGSize = .zero

    private var debouncer = GuidanceDebouncer()

    /// One analysed frame: debounce the state, keep the passing rows for the
    /// ready outline.
    func observe(rows: [PumpRowDetector.Row], frameSize: CGSize, analysisMs: Int) {
        framesAnalysed += 1
        lastAnalysisMs = analysisMs
        self.frameSize = frameSize
        state = debouncer.observe(CaptureGuidanceState.classify(rows: rows))
        overlayRects = state == .ready
            ? rows.filter { PumpDisplayCapture.passesSize($0) }.map(\.bounds)
            : []
    }

    func reset() {
        state = .searching
        overlayRects = []
        framesAnalysed = 0
        lastAnalysisMs = 0
        frameSize = .zero
        debouncer.reset()
    }
}

/// The video-frame driver: runs the detector off the main thread on a serial
/// queue, at most one analysis per `minimumInterval`, and hands the rows to
/// `onRows`. The same serial queue is the sample-buffer delegate queue, so at
/// most one analysis is in flight and the frames that arrive meanwhile are
/// dropped (`AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames`).
final class PreviewFrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias RowsHandler = @Sendable ([PumpRowDetector.Row], CGSize, Int) -> Void

    /// ~10 fps: the detector's rows barely change between adjacent frames, and
    /// the preview frame is not the frame the shutter will use.
    static let minimumInterval: CFAbsoluteTime = 0.1

    private let queue = DispatchQueue(label: "app.tankbook.preview-guidance")
    private let lock = NSLock()
    private var reader: PumpReaderHandle?
    private var active = false
    private var lastAnalysisAt: CFAbsoluteTime = 0
    private let onRows: RowsHandler

    init(onRows: @escaping RowsHandler) {
        self.onRows = onRows
        super.init()
    }

    func attach(to output: AVCaptureVideoDataOutput) {
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func set(reader: PumpReaderHandle?, active: Bool) {
        lock.lock()
        self.reader = reader
        self.active = active
        lock.unlock()
    }

    /// Runs the detector over a decoded frame - the simulator's
    /// `-captureCameraTestFrame` double, which has no camera to deliver one.
    func feed(_ image: CGImage) {
        let box = ImageBox(image: image)
        queue.async { [weak self] in
            self?.analyze(size: CGSize(width: box.image.width, height: box.image.height)) { reader in
                reader.detectedRows(in: box.image)
            }
        }
    }

    func captureOutput(_ output: AVCaptureVideoDataOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        analyze(size: size) { reader in reader.detectedRows(in: pixelBuffer) }
    }

    private func analyze(size: CGSize, _ work: (PumpReaderHandle) -> [PumpRowDetector.Row]) {
        lock.lock()
        let active = active
        let reader = reader
        let now = CFAbsoluteTimeGetCurrent()
        let throttled = now - lastAnalysisAt < Self.minimumInterval
        if active, reader != nil, !throttled { lastAnalysisAt = now }
        lock.unlock()
        guard active, let reader, !throttled else { return }
        let started = CFAbsoluteTimeGetCurrent()
        let rows = work(reader)
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        #if DEBUG
        // The device's number is RV.295's; this is the simulator's proxy.
        print("PU.40b preview guidance: \(ms) ms, \(rows.count) rows, "
              + "frame \(Int(size.width))x\(Int(size.height))")
        #endif
        onRows(rows, size, ms)
    }
}

/// Carries a decoded frame across the analyzer's queue boundary; `CGImage` is
/// immutable and safe to share, but not `Sendable` to the compiler.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage
}
