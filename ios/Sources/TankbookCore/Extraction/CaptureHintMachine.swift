import CoreGraphics
import Foundation

/// What the capture screen says about the live preview before the shutter
/// (PJ.16, docs/ERRORS.md -> Capture): too dark, or nothing to read in frame.
/// A hint never blocks the shutter and never hides "Type it" (hard rule 15).
public enum CaptureHint: String, Equatable, Sendable {
    case none
    /// The preview is too dark to read: "Dark – tap for torch".
    case dark
    /// Nothing detected for a while: "Fill the frame with the receipt – or type it instead."
    case fillFrame
}

/// The hint decision as a pure function of preview signals over time, so it is
/// tested without a camera. Inputs arrive as frames are sampled (`observe`) and
/// as the clock ticks without frames (`tick`); the output is the hint to show
/// and whether auto-shutter fires.
public struct CaptureHintMachine: Sendable {

    /// The tunables (docs/PRACTICES.md -> constants table, tier C).
    public struct Tuning: Sendable, Equatable {
        /// Smoothed mean luma (0...1) below which the preview counts as dark.
        public var darkBelow: Double = 0.16
        /// Smoothed luma above which a dark hint clears - the gap is hysteresis,
        /// so a scene at the threshold does not flicker the hint.
        public var lightAbove: Double = 0.22
        /// The luma smoothing time constant, seconds.
        public var smoothingSeconds: Double = 1.0
        /// Seconds with nothing detected before "fill the frame" appears.
        public var noDetectionSeconds: Double = 4.0
        /// Seconds a document must hold still before auto-shutter fires.
        public var steadySeconds: Double = 0.7
        /// How far (normalised) a document's corners may move and still count as steady.
        public var steadyTolerance: Double = 0.03

        public init() {}
    }

    public let tuning: Tuning
    private var smoothedLuma: Double?
    private var lastObservationAt: TimeInterval?
    private var isDark = false
    private var lastDetectionAt: TimeInterval
    private var steadyRect: CGRect?
    private var steadySince: TimeInterval?
    private var autoShutterFired = false
    public private(set) var hint: CaptureHint = .none

    public init(startedAt: TimeInterval, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        lastDetectionAt = startedAt
    }

    /// One sampled preview frame. `luma` is the frame's mean luminance (0...1),
    /// `document` the detected document's normalised bounds (nil when none),
    /// and `displayInView` is true while the pump-display guidance sees rows -
    /// that counts as "something to read" too.
    @discardableResult
    public mutating func observe(luma: Double?, document: CGRect?, displayInView: Bool,
                                 at time: TimeInterval) -> CaptureHint {
        if let luma {
            if let previous = smoothedLuma, let last = lastObservationAt {
                let alpha = min(1, max(0, (time - last) / tuning.smoothingSeconds))
                smoothedLuma = previous + alpha * (luma - previous)
            } else {
                smoothedLuma = luma
            }
            lastObservationAt = time
            if let smoothed = smoothedLuma {
                if isDark, smoothed > tuning.lightAbove { isDark = false }
                if !isDark, smoothed < tuning.darkBelow { isDark = true }
            }
        }
        if document != nil || displayInView {
            lastDetectionAt = time
        }
        trackSteadiness(document, at: time)
        return tick(at: time)
    }

    /// The clock moved without a new frame (or with one already folded in).
    @discardableResult
    public mutating func tick(at time: TimeInterval) -> CaptureHint {
        if isDark {
            hint = .dark
        } else if time - lastDetectionAt >= tuning.noDetectionSeconds {
            hint = .fillFrame
        } else {
            hint = .none
        }
        return hint
    }

    /// True exactly once per session: a document has held still for
    /// `steadySeconds`. The caller decides whether auto-shutter is enabled.
    public mutating func takeAutoShutter(at time: TimeInterval) -> Bool {
        guard !autoShutterFired, let since = steadySince,
              time - since >= tuning.steadySeconds else { return false }
        autoShutterFired = true
        return true
    }

    private mutating func trackSteadiness(_ document: CGRect?, at time: TimeInterval) {
        guard let document else {
            steadyRect = nil
            steadySince = nil
            return
        }
        if let previous = steadyRect, Self.isClose(previous, document, tolerance: tuning.steadyTolerance) {
            return
        }
        steadyRect = document
        steadySince = time
    }

    private static func isClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: Double) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}
