import Foundation
import Testing
@testable import TankbookCore

// P2.7: the pump-photo accuracy gate and the capture-path decision
// (docs/TASKS.md -> "the gate IS the check"). Pure and deterministic: no
// Vision, no corpus scoring - the real corpus number is asserted separately in
// AccuracyRatchetTests' Vision-gated suite, and these tests construct the
// accuracy input so the gate's two sides are exercised exactly.

@Suite("Pump-photo accuracy gate")
struct PumpPhotoGateTests {

    @Test("the gate fails when the flag is on but accuracy is below 95%")
    func flagOnBelowThresholdIsAViolation() {
        #expect(PumpPhotoGate.violation(flagEnabled: true, accuracy: 0.0) != nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, accuracy: 0.40) != nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, accuracy: 0.94) != nil)
    }

    @Test("the gate passes with the flag off, whatever the accuracy")
    func flagOffIsNeverAViolation() {
        #expect(PumpPhotoGate.violation(flagEnabled: false, accuracy: 0.0) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: false, accuracy: 0.40) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: false, accuracy: 1.0) == nil)
    }

    @Test("the gate passes when the flag is on at or above 95%")
    func flagOnAtOrAboveThresholdPasses() {
        #expect(PumpPhotoGate.violation(flagEnabled: true, accuracy: 0.95) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, accuracy: 0.96) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, accuracy: 1.0) == nil)
    }
}

@Suite("Pump-photo capture path")
struct PumpPhotoCaptureTests {

    private let extraction = FuelExtraction(liters: 60.25, unitPrice: 76.24, total: 4593.46,
                                            currency: .rub, date: "17.08.2026")

    @Test("off degrades to the manual form with nothing pre-filled")
    func offProducesNoPrefill() {
        #expect(PumpPhotoCapture.prefill(pumpPhotoEnabled: false, extraction: nil) == nil)
    }

    @Test("off produces no prefill even when the parser resolved fields")
    func offDiscardsTheExtraction() {
        #expect(PumpPhotoCapture.prefill(pumpPhotoEnabled: false, extraction: extraction) == nil)
    }

    @Test("on pre-fills the extraction as a default input")
    func onPrefills() {
        #expect(PumpPhotoCapture.prefill(pumpPhotoEnabled: true, extraction: extraction) == extraction)
    }

    @Test("on with no extraction still yields an empty form")
    func onWithNilExtractionIsEmpty() {
        #expect(PumpPhotoCapture.prefill(pumpPhotoEnabled: true, extraction: nil) == nil)
    }
}
