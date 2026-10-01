import CoreGraphics
import CoreVideo
import Foundation
import Observation
import TankbookCore
import Vision

/// PJ.16 - the capture screen's readiness hints: "Dark – tap for torch" and
/// "Fill the frame – or type it instead.", and the optional auto-shutter. The
/// decision is `CaptureHintMachine` (core, pure); this model feeds it the
/// sampled preview signals and the clock, and publishes the hint the caption
/// shows. A hint never blocks the shutter and never hides "Type it" (hard rule 15).
@MainActor
@Observable
final class CaptureHints {
    /// UserDefaults key of the auto-shutter setting (device-local, off by default).
    static let autoShutterKey = "capture.autoShutter"
    /// How often the clock advances the machine when no frame arrives.
    static let tickInterval: Duration = .milliseconds(250)

    private(set) var hint: CaptureHint = .none
    @ObservationIgnored private var machine: CaptureHintMachine?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var displayInView: () -> Bool = { false }
    /// Fired once per session when auto-shutter is on and a document holds still.
    @ObservationIgnored var onAutoShutter: (() -> Void)?

    var isRunning: Bool { machine != nil }

    func start(displayInView: @escaping () -> Bool) {
        guard machine == nil else { return }
        self.displayInView = displayInView
        machine = CaptureHintMachine(startedAt: Self.now)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        machine = nil
        hint = .none
    }

    /// One sampled frame's signals.
    func observe(luma: Double?, document: CGRect?) {
        guard var machine else { return }
        let time = Self.now
        let next = machine.observe(luma: luma, document: document, displayInView: displayInView(), at: time)
        let fire = UserDefaults.standard.bool(forKey: Self.autoShutterKey) && machine.takeAutoShutter(at: time)
        self.machine = machine
        publish(next)
        if fire {
            AppLog.shared.emit(CaptureReadiness(action: "autoShutter"))
            onAutoShutter?()
        }
    }

    private func tick() {
        #if DEBUG
        if let injected = Self.injectedLuma {
            observe(luma: injected, document: nil)
            return
        }
        #endif
        guard var machine else { return }
        let next = machine.tick(at: Self.now)
        self.machine = machine
        publish(next)
    }

    private func publish(_ next: CaptureHint) {
        guard next != hint else { return }
        hint = next
        if next != .none {
            AppLog.shared.emit(CaptureReadiness(action: "hint.\(next.rawValue)"))
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    #if DEBUG
    /// `-captureHintLuma <0...1>`: a constant preview luminance for UI tests and
    /// screenshots - the simulator has no camera to measure one.
    static var injectedLuma: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-captureHintLuma"), index + 1 < arguments.count else {
            return nil
        }
        return Double(arguments[index + 1])
    }
    #endif
}

/// Measures a preview frame's mean luminance and finds a document in it, on the
/// frame analyzer's queue, at most every `minimumInterval`. Hands both to the
/// main actor. Shape only leaves this type: a number and a rectangle.
final class CaptureHintSampler: @unchecked Sendable {
    typealias Handler = @Sendable (Double?, CGRect?) -> Void
    static let minimumInterval: CFAbsoluteTime = 0.25
    /// Grid of sampled points per axis for the luminance estimate.
    private static let lumaGrid = 24
    private let handler: Handler
    private var lastSampleAt: CFAbsoluteTime = 0

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Called on the analyzer's serial queue for every frame.
    func sample(_ pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSampleAt >= Self.minimumInterval else { return }
        lastSampleAt = now
        handler(Self.meanLuma(pixelBuffer), Self.document(in: pixelBuffer))
    }

    /// Mean luminance (0...1) over a sparse grid: the Y plane of a bi-planar
    /// frame, or Rec. 601 weights over a BGRA one.
    static func meanLuma(_ buffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
        let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        guard let base, width > 0, height > 0 else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        var count = 0
        for row in 0..<lumaGrid {
            let y = (row * 2 + 1) * height / (lumaGrid * 2)
            for column in 0..<lumaGrid {
                let x = (column * 2 + 1) * width / (lumaGrid * 2)
                if planar {
                    total += Double(bytes[y * stride + x])
                } else {
                    let pixel = y * stride + x * 4
                    total += 0.114 * Double(bytes[pixel]) + 0.587 * Double(bytes[pixel + 1])
                        + 0.299 * Double(bytes[pixel + 2])
                }
                count += 1
            }
        }
        return total / Double(count) / 255
    }

    /// The most confident document Vision finds, as normalised bounds.
    static func document(in buffer: CVPixelBuffer) -> CGRect? {
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
        guard let best = request.results?.max(by: { $0.confidence < $1.confidence }),
              best.confidence >= 0.6 else { return nil }
        return best.boundingBox
    }
}
