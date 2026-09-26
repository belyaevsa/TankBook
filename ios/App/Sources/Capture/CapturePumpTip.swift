import Foundation

/// The first-use tip J4 names ("no receipt? Shoot the pump"): the
/// capture caption says once that a pump display is a target, because nothing
/// else on the screen does while pump reading is framed as alpha
/// (`CaptureView.captureCaption`). It is shown on the first fill-up capture
/// session and never again - taking it marks it seen, so a relaunch or a
/// second capture keeps the ordinary caption.
enum CapturePumpTip {
    static let seenKey = "capture.pumpTipSeen"

    /// True once per install: the first call returns true and records the tip
    /// as seen; every later call returns false.
    static func takeIfUnseen(_ defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: seenKey) else { return false }
        defaults.set(true, forKey: seenKey)
        return true
    }

    /// Test-only hooks, as `CaptureAlphaNoticeState` has: `-pumpTipReset`
    /// makes the next capture session the first, `-pumpTipSeen` skips the tip
    /// for a test that asserts the ordinary caption.
    #if DEBUG
    static func resetForTestsIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-pumpTipReset") { UserDefaults.standard.removeObject(forKey: seenKey) }
        if arguments.contains("-pumpTipSeen") { UserDefaults.standard.set(true, forKey: seenKey) }
    }
    #endif
}
