import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// PJ.16: the capture hints and auto-shutter as a pure function of preview
/// signals over time. Oracles are the named tunables in `CaptureHintMachine.Tuning`.
@Suite("Capture readiness hints (PJ.16)")
struct CaptureHintMachineTests {
    private let tuning = CaptureHintMachine.Tuning()
    private let receipt = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    @Test func aDarkPreviewShowsTheDarkHintAndALightOneDoesNot() {
        var dark = CaptureHintMachine(startedAt: 0)
        let result1 = dark.observe(luma: tuning.darkBelow - 0.05, document: receipt, displayInView: false, at: 0.1)
        #expect(result1 == .dark)
        var light = CaptureHintMachine(startedAt: 0)
        let result2 = light.observe(luma: 0.5, document: receipt, displayInView: false, at: 0.1)
        #expect(result2 == .none)
    }

    /// Between the two thresholds the hint keeps its state: a scene sitting at
    /// the dark threshold does not flicker.
    @Test func theDarkHintHasHysteresis() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.05, document: receipt, displayInView: false, at: 0)
        let between = (tuning.darkBelow + tuning.lightAbove) / 2
        // Long enough for the smoothing to reach the new value.
        let result3 = machine.observe(luma: between, document: receipt, displayInView: false, at: 3)
        #expect(result3 == .dark)
        let result4 = machine.observe(luma: 0.6, document: receipt, displayInView: false, at: 6)
        #expect(result4 == .none)
    }

    /// One dark frame in a bright scene does not raise the hint: the luma is smoothed.
    @Test func oneDarkFrameDoesNotFlickerTheHint() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.6, document: receipt, displayInView: false, at: 0)
        let result5 = machine.observe(luma: 0.0, document: receipt, displayInView: false, at: 0.1)
        #expect(result5 == .none)
    }

    @Test func nothingDetectedForTheWindowShowsFillTheFrame() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.5, document: nil, displayInView: false, at: 1)
        let result6 = machine.tick(at: tuning.noDetectionSeconds - 0.1)
        #expect(result6 == .none)
        let result7 = machine.tick(at: tuning.noDetectionSeconds)
        #expect(result7 == .fillFrame)
    }

    /// A detection resets the window: the hint waits a full window from the
    /// last thing seen, not from when the screen opened.
    @Test func aDetectionResetsTheWindow() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.5, document: receipt, displayInView: false, at: 3)
        let result8 = machine.tick(at: 3 + tuning.noDetectionSeconds - 0.1)
        #expect(result8 == .none)
        let result9 = machine.tick(at: 3 + tuning.noDetectionSeconds)
        #expect(result9 == .fillFrame)
    }

    /// A pump display in view counts as something to read: no fill hint while
    /// the display guidance sees rows (it has its own captions).
    @Test func aPumpDisplayInViewSuppressesTheFillHint() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.5, document: nil, displayInView: true, at: 5)
        let result10 = machine.tick(at: 5 + tuning.noDetectionSeconds - 0.1)
        #expect(result10 == .none)
    }

    /// Dark wins over fill: the torch is the more useful next step.
    @Test func darkTakesPrecedenceOverFillTheFrame() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.02, document: nil, displayInView: false, at: 0)
        let result11 = machine.tick(at: 10)
        #expect(result11 == .dark)
    }

    @Test func autoShutterFiresOnceAfterTheDocumentHoldsStill() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.5, document: receipt, displayInView: false, at: 1)
        let result12 = machine.takeAutoShutter(at: 1 + tuning.steadySeconds - 0.1)
        #expect(!result12)
        machine.observe(luma: 0.5, document: receipt.offsetBy(dx: 0.01, dy: 0), displayInView: false,
                        at: 1 + tuning.steadySeconds - 0.05)
        let result13 = machine.takeAutoShutter(at: 1 + tuning.steadySeconds)
        #expect(result13)
        let result14 = machine.takeAutoShutter(at: 5)
        #expect(!result14, "once per session")
    }

    /// A document that moves restarts the steadiness clock.
    @Test func aMovingDocumentDoesNotFireAutoShutter() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.5, document: receipt, displayInView: false, at: 1)
        machine.observe(luma: 0.5, document: receipt.offsetBy(dx: 0.2, dy: 0), displayInView: false, at: 1.5)
        let result15 = machine.takeAutoShutter(at: 1.9)
        #expect(!result15)
        let result16 = machine.takeAutoShutter(at: 1.5 + tuning.steadySeconds)
        #expect(result16)
    }

    @Test func noDocumentNeverFiresAutoShutter() {
        var machine = CaptureHintMachine(startedAt: 0)
        machine.observe(luma: 0.5, document: nil, displayInView: true, at: 1)
        let result17 = machine.takeAutoShutter(at: 10)
        #expect(!result17)
    }
}
