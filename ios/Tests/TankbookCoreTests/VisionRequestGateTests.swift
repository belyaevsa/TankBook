import Foundation
import Testing
@testable import TankbookCore

// RV.52 - the L1 for the Vision request gate. The gate's contract is a pure
// decision: it admits at most `limit` bodies concurrently, and it releases the
// slot on both the success and the throwing path. A gate that leaked a slot on
// an error would deadlock the suite the first time an OCR call fails, so the
// throw path is asserted directly rather than trusted.
//
// The callers below are raw `Thread`s, deliberately not `DispatchQueue`
// (`concurrentPerform`): the gate itself dispatches each body to a background
// dispatch queue, so driving it from the global queue competes with its own
// work and makes the peak read unreliable. Real threads leave the dispatch pool
// free for the bodies, so the peak measures the gate's bound and nothing else.

@Suite("Vision request gate (RV.52)")
struct VisionRequestGateTests {

    private enum TestError: Error { case boom }

    /// Tracks the peak number of bodies executing at once, across threads.
    private final class Peak: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private var max = 0

        func enter() {
            lock.lock()
            current += 1
            max = Swift.max(max, current)
            lock.unlock()
        }

        func exit() {
            lock.lock()
            current -= 1
            lock.unlock()
        }

        var peak: Int {
            lock.lock()
            defer { lock.unlock() }
            return max
        }
    }

    /// Runs `count` callers on raw threads and returns the peak body concurrency.
    private func peakConcurrency(gate: VisionRequestGate, count: Int) -> Int {
        let peak = Peak()
        let group = DispatchGroup()
        for _ in 0..<count {
            group.enter()
            Thread.detachNewThread {
                try? gate.withSlot {
                    peak.enter()
                    Thread.sleep(forTimeInterval: 0.1)
                    peak.exit()
                }
                group.leave()
            }
        }
        group.wait()
        return peak.peak
    }

    @Test("the gate admits at most its limit concurrently, and not just one")
    func gateAdmitsAtMostItsLimitConcurrently() {
        let peak = peakConcurrency(gate: VisionRequestGate(limit: 4), count: 40)
        // 40 callers would run ~12+ at once unconstrained on this machine; the
        // gate must hold them to 4, and must actually use all 4 (a strict-serial
        // gate that admitted one at a time would also pass "<=" but fail "==").
        #expect(peak <= 4)
        #expect(peak == 4)
    }

    @Test("the gate releases its slot when the body throws")
    func gateReleasesItsSlotWhenTheBodyThrows() {
        let gate = VisionRequestGate(limit: 3)
        do {
            _ = try gate.withSlot { () -> Int in throw TestError.boom }
        } catch {
            // expected
        }
        // If the throw leaked a slot, the gate would now admit only 2; the
        // workload below must still reach the full limit of 3.
        #expect(peakConcurrency(gate: gate, count: 30) == 3)
    }

    @Test("the gate returns the body's value")
    func gateReturnsTheBodysValue() throws {
        let gate = VisionRequestGate(limit: 2)
        let value = try gate.withSlot { 42 }
        #expect(value == 42)
    }
}
