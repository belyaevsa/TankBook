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

    @Test("the gate fails when the flag is on but precision is below 99%")
    func flagOnBelowPrecisionIsAViolation() {
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 0.0, coverage: 1.0) != nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 0.90, coverage: 1.0) != nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 0.98, coverage: 1.0) != nil)
    }

    @Test("the gate fails when the flag is on but coverage is below the floor")
    func flagOnBelowCoverageIsAViolation() {
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 1.0, coverage: 0.0) != nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 1.0, coverage: 0.59) != nil)
    }

    @Test("the gate passes with the flag off, whatever the precision and coverage")
    func flagOffIsNeverAViolation() {
        #expect(PumpPhotoGate.violation(flagEnabled: false, precision: 0.0, coverage: 0.0) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: false, precision: 0.4, coverage: 0.4) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: false, precision: 1.0, coverage: 1.0) == nil)
    }

    @Test("the gate passes when the flag is on at or above precision and coverage")
    func flagOnAtOrAboveThresholdPasses() {
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 0.99, coverage: 0.60) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 0.995, coverage: 0.61) == nil)
        #expect(PumpPhotoGate.violation(flagEnabled: true, precision: 1.0, coverage: 1.0) == nil)
    }

    @Test("allowsPumpPhoto is the reader's measured precision and coverage against the gate")
    func allowsPumpPhotoRequiresBoth() {
        #expect(PumpPhotoGate.precisionThreshold == 0.99)
        #expect(PumpPhotoGate.coverageFloor == 0.60)
        #expect(PumpPhotoGate.allowsPumpPhoto
                == (PumpPhotoGate.readerPrecision >= 0.99 && PumpPhotoGate.readerCoverage >= 0.60))
    }

    /// The owner turned pump photo on (2026-09-26). The bundled flag may say on
    /// only while the build's own measured accuracy clears the gate - a retrain
    /// that dropped below it fails here until the flag is turned back off.
    @Test("the bundled flag is on only while the build clears the gate")
    func bundledFlagIsOnOnlyUnderTheGate() throws {
        let flag = try ConfigDefaults.bundledAppConfig().flags["pumpPhoto"]
        #expect(flag?.enabled == true)
        #expect(PumpPhotoGate.violation(flagEnabled: flag?.enabled ?? false,
                                        precision: PumpPhotoGate.readerPrecision,
                                        coverage: PumpPhotoGate.readerCoverage) == nil)
    }
}

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Pump-photo capture path")
struct PumpPhotoCaptureTests {

    private let extraction = FuelExtraction(liters: 60.25, unitPrice: dec("76.24"),
                                            total: dec("4593.46"),
                                            currency: .rub, date: "17.08.2026")

    @Test("off still offers the reading, framed as alpha (decision 7)")
    func offOffersTheReadingAsAlpha() {
        let outcome = PumpPhotoCapture.outcome(pumpPhotoEnabled: false, extraction: extraction)
        #expect(outcome.extraction == extraction)
        #expect(outcome.alpha)
    }

    @Test("off with nothing read is the empty form, still alpha")
    func offWithNothingReadIsEmpty() {
        let outcome = PumpPhotoCapture.outcome(pumpPhotoEnabled: false, extraction: nil)
        #expect(outcome.extraction == nil)
        #expect(outcome.alpha)
    }

    @Test("on pre-fills the extraction as an ordinary default input")
    func onPrefills() {
        let outcome = PumpPhotoCapture.outcome(pumpPhotoEnabled: true, extraction: extraction)
        #expect(outcome.extraction == extraction)
        #expect(!outcome.alpha)
    }

    @Test("on with no extraction still yields an empty form")
    func onWithNilExtractionIsEmpty() {
        #expect(PumpPhotoCapture.prefill(pumpPhotoEnabled: true, extraction: nil) == nil)
    }
}
