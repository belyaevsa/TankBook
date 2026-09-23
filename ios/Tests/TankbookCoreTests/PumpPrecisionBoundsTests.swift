import Foundation
import Testing

/// The bounds against the values `agents/research/PU.68.md` computed by hand
/// (§4 and §5.1), to four decimals: a bound that does not move with the error
/// count, or a certificate the sample cannot support, fails here.
@Suite("Pump precision bounds")
struct PumpPrecisionBoundsTests {
    private func close(_ got: Double, _ want: Double) -> Bool { abs(got - want) < 0.00006 }

    private struct IntervalCase {
        let x: Int, n: Int, lower: Double, upper: Double, wilson1s: Double, cp1s: Double
    }

    private struct BoundCase {
        let k: Int, n: Int, delta: Double, ucb: Double
    }

    @Test("Wilson and Clopper-Pearson match the research note's table")
    func intervalsMatchTheNote() {
        let cases = [
            IntervalCase(x: 45, n: 45, lower: 0.9213, upper: 1.0000, wilson1s: 0.9433, cp1s: 0.9356),
            IntervalCase(x: 51, n: 52, lower: 0.8988, upper: 0.9966, wilson1s: 0.9183, cp1s: 0.9120),
            IntervalCase(x: 54, n: 54, lower: 0.9336, upper: 1.0000, wilson1s: 0.9523, cp1s: 0.9460),
            IntervalCase(x: 111, n: 112, lower: 0.9512, upper: 0.9984, wilson1s: 0.9610, cp1s: 0.9583),
        ]
        for c in cases {
            let two = PumpPrecisionBounds.wilson(c.x, c.n, z: PumpPrecisionBounds.z95TwoSided)
            #expect(close(two.lower, c.lower), "\(c.x)/\(c.n) Wilson 2s lower \(two.lower)")
            #expect(close(two.upper, c.upper), "\(c.x)/\(c.n) Wilson 2s upper \(two.upper)")
            let one = PumpPrecisionBounds.wilson(c.x, c.n, z: PumpPrecisionBounds.z95OneSided).lower
            #expect(close(one, c.wilson1s), "\(c.x)/\(c.n) Wilson 1s lower \(one)")
            let cp = PumpPrecisionBounds.clopperPearsonLower(c.x, c.n, alpha: 0.05)
            #expect(close(cp, c.cp1s), "\(c.x)/\(c.n) CP 1s lower \(cp)")
        }
    }

    @Test("the exact binomial UCB matches the note, and 250 clean photos cannot certify 0.01 at 95 %")
    func upperBoundsMatchTheNote() {
        let cases = [
            BoundCase(k: 0, n: 668, delta: 0.05, ucb: 0.0045), BoundCase(k: 1, n: 668, delta: 0.05, ucb: 0.0071),
            BoundCase(k: 2, n: 668, delta: 0.05, ucb: 0.0094), BoundCase(k: 3, n: 668, delta: 0.05, ucb: 0.0116),
            BoundCase(k: 0, n: 250, delta: 0.05, ucb: 0.0119), BoundCase(k: 1, n: 250, delta: 0.05, ucb: 0.0188),
            BoundCase(k: 0, n: 250, delta: 0.10, ucb: 0.0092), BoundCase(k: 1, n: 250, delta: 0.10, ucb: 0.0155),
        ]
        for c in cases {
            let ucb = PumpPrecisionBounds.binomialUCB(c.k, c.n, delta: c.delta)
            #expect(close(ucb, c.ucb), "k=\(c.k) n=\(c.n) delta=\(c.delta): \(ucb)")
        }
        // Falsifier F3 of the note: no error count certifies a 1 % photo
        // error rate at 95 % from 250 photos.
        #expect(PumpPrecisionBounds.binomialUCB(0, 250, delta: 0.05) > 0.01)
    }

    @Test("a bound moves with the error count")
    func boundsMoveWithErrors() {
        let clean = PumpPrecisionBounds.wilson(52, 52, z: PumpPrecisionBounds.z95OneSided).lower
        let oneWrong = PumpPrecisionBounds.wilson(51, 52, z: PumpPrecisionBounds.z95OneSided).lower
        #expect(oneWrong < clean)
        #expect(PumpPrecisionBounds.binomialUCB(1, 250, delta: 0.05) > PumpPrecisionBounds.binomialUCB(0, 250, delta: 0.05))
    }
}
